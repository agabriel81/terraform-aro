# Terraforming a public Azure Red Hat OpenShift (ARO), install OpenShift ServiceMesh using OpenShift GitOps and using a custom CA for ServiceMesh workload by Cert-Manager Operator

Prerequisites and versions:

```
- Terraform (CLI): v1.8.3
- az (CLI): 2.60.0
- oc (CLI): version depend on the cluster version
```
```
- ARO: 4.12
- OpenShift GitOps: 1.12
- OpenShift Kiali: 1.73
- OpenShift Jaeger: 1.53
- OpenShift ServiceMesh: 2.5
- OpenShift Cert-Manager: 1.12
```

Clone the repository and change to repo directory:
```
$ https://github.com/agabriel81/terraform-aro.git
$ cd terraform-aro
```

Start the Terraform process by passing few variables:
```
- pull_secret (Red Hat pull secret)
- cluster_domain
- cluster_version
- location (Azure region)
- resourcegroup_name (Azure ResourceGroup)
- cluster_name
```
```
$ terraform init
$ terraform validate
$ terraform plan --var 'pull_secret={"auths":{"arosvc.azurecr.io"...<your pull secret>' --var 'cluster_domain=<your cluster domain>' --var 'cluster_version=<your cluster version>' --var 'location=<your cluster location>' --var 'resourcegroup_name=<your cluster resource group>' --var 'cluster_name=<your cluster name>'
$ terraform apply --var 'pull_secret={"auths":{"arosvc.azurecr.io"...<your pull secret>' --var 'cluster_domain=agabriel-ger' --var 'cluster_version=4.12.25' --var 'location=germanywestcentral' --var 'resourcegroup_name=aro-ger-agabriel' --var 'cluster_name=aro-ger-cluster1'
```

After completing the installation, retrieve ARO credentials, ARO console and ARO API URL:

```
$ az aro list-credentials --name <cluster_name> --resource-group <resourcegroup_name>
$ az aro show --name <cluster_name> --resource-group <resourcegroup_name> --query "consoleProfile.url" -o tsv
$ az aro show -g <resourcegroup_name -n <cluster_name> --query apiserverProfile.url -o tsv 
$ oc login <API URL> -u kubeadmin
```

Access the ARO console and install the OpenShift GitOps using the official documentation [1] (version 1.12 at the time of writing).

Create a GitOps application for installating the Cert-manager, Kiali, Jaeger and ServiceMesh Operators, with ServiceMeshControlPlane and ServiceMeshMemberRoll CRDs pointing the `mesh_gitops_cluster` directory of this repository. 

This process requires `cluster-admin` permissions to the `openshift-gitops-argocd-application-controller` ServiceAccount:

```
$ oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops
$ cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mesh-cluster
  namespace: openshift-gitops
spec:
  destination:
    name: ''
    namespace: ''
    server: 'https://kubernetes.default.svc'
  source:
    path: mesh_gitops_cluster
    repoURL: 'https://github.com/agabriel81/terraform-aro.git'
    targetRevision: master
  sources: []
  project: default
  syncPolicy:
    retry:
      limit: 5
      backoff:
        duration: 15s
        maxDuration: 3m0s
        factor: 2
EOF
```

The GitOps Application resources are configured with "sync-waves" to respect creation order but you can ajust the `retry` option on GitOps for achieving more consistency.

The ServiceMesh control plane installation will fail but it's expected because it needs the custom Istio Gateway certificate which will be created in next steps.

Create the CA Issuer for the `Cert-Manager` Operator, it will sign the end certificate for OpenShift ServiceMesh.

Create a secret containing your custom CA and then the Cert-Manager resources. Fill the resources based on your environment:

```
$ oc -n cert-manager create secret generic ca-key-pair --from-file=tls.key=<CA key> --from-file=tls.crt=<CA certificate>
$ oc create -f cert-manager_manifests/clusterissuer.yaml
$ cp -p cert-manager_manifests/certificate.yaml /tmp/certificate.yaml
$ vi /tmp/certificate.yaml
$ oc create -f /tmp/certificate.yaml
```

The OpenShift ServiceMesh Istio Gateway is already configured for mounting a custom certificate and it's needed to restart the Istio Gateway pod to mount the newly created custom certificate, signed by your custom CA and saved into the secret `istio-ingressgateway-custom-certs`

And finally, let's deploy some workload into the ServiceMesh using the infamous `bookinfo` application:

```
$ cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mesh-workload
  namespace: openshift-gitops
spec:
  destination:
    name: ''
    namespace: 'bookinfo'
    server: 'https://kubernetes.default.svc'
  source:
    path: mesh_gitops_workload
    repoURL: 'https://github.com/agabriel81/terraform-aro.git'
    targetRevision: master
  sources: []
  project: default
  syncPolicy:
    retry:
      limit: 5
      backoff:
        duration: 15s
        maxDuration: 3m0s
        factor: 2
EOF
```


REFERENCE

[1] https://docs.openshift.com/gitops/1.12/understanding_openshift_gitops/about-redhat-openshift-gitops.html

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster

