# Terraforming a public Azure Red Hat OpenShift (ARO) cluster, install OpenShift ServiceMesh using OpenShift GitOps with custom CA for ServiceMesh workload by Cert-Manager Operator

Prerequisites and versions:

```
- Terraform (CLI): v1.9.2
- az (CLI): 2.62.0
- oc (CLI): version depend on the cluster version
- custom rootCA certificate and key
```
```
- ARO: 4.13
- OpenShift GitOps: 1.13
- OpenShift Kiali: 1.73
- OpenShift TempoStack: 2.4
- OpenShift ServiceMesh: 2.5
- OpenShift Cert-Manager: 1.12
```

Clone the repository and change to repo directory:
```
$ git clone https://github.com/agabriel81/terraform-aro.git
$ cd terraform-aro/terraform-code
```

Start the Terraform process by passing few variables:
```
$ export TF_VAR_pull_secret='{"auths":{"arosvc.azurecr.io....'
$ export TF_VAR_azure_app_name=agabriel-app-aro-ita
$ export TF_VAR_cluster_domain=agabriel-ger
$ export TF_VAR_cluster_version=4.13.40
$ export TF_VAR_location=germanywestcentral
$ export TF_VAR_resourcegroup_name=aro-ger-agabriel
$ export TF_VAR_cluster_name=aro-ger-cluster1
$ export TF_VAR_tm_route=agabriel-aro-tm.trafficmanager.net
```

Deploy all Azure and OpenShift resources using Terraform:

```
$ terraform init
$ terraform validate
$ terraform plan 
$ terraform apply 
```

After completing the installation, retrieve ARO credentials, ARO console and ARO API URL:

```
$ az aro list-credentials --name ${TF_VAR_cluster_name} --resource-group ${TF_VAR_resourcegroup_name}
$ az aro show --name ${TF_VAR_cluster_name} --resource-group ${TF_VAR_resourcegroup_name} --query "consoleProfile.url" -o tsv
$ az aro show -g ${TF_VAR_resourcegroup_name} -n ${TF_VAR_cluster_name} --query apiserverProfile.url -o tsv 
$ oc login <API URL> -u kubeadmin
```

Access the ARO console and **install the OpenShift GitOps** using the official documentation [1] (version 1.12 at the time of writing).

Create a GitOps application for installating the Cert-manager, Kiali, Jaeger and ServiceMesh Operators, with ServiceMeshControlPlane and ServiceMeshMemberRoll CRDs pointing the `mesh_gitops_cluster` directory of this repository. 

This process requires `cluster-admin` permissions to the `openshift-gitops-argocd-application-controller` ServiceAccount:

```
$ oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops
```
```
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
    targetRevision: mtls_tempo
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

Access the OpenShift GitOps ArgoCD instance and manually sync the `mesh-cluster` Application.

The ServiceMesh Control Plane is configured with MTLS enabled and it will expect a custom CA which needs to be configured via a secret:

```
$ oc create secret generic cacerts -n istio-system --from-file=<path>/ca-cert.pem \
    --from-file=<path>/ca-key.pem --from-file=<path>/root-cert.pem \
    --from-file=<path>/cert-chain.pem
```

Below a snippet of the MTLS and custom CA configuration in the SMCP (ServiceMeshControlPlane) CRD:

```
  spec:
    security:
      dataPlane:
        mtls: true
    certificateAuthority:
      type: Istiod
      istiod:
        type: PrivateKey
        privateKey:
          rootCADir: /etc/cacerts
```

You may need to restart the ServiceMesh Control Plane component:

```
$ oc -n istio-system delete pods -l 'app in (istiod,istio-ingressgateway, istio-egressgateway)'
```

Let's configured the TempoStack S3 reference secret:

```
oc apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: azure-storage-secret
  namespace: tracing-system
stringData:
  name: <name>
  container: <Azure container blob name>
  account_name: <Azure storage account name>
  account_key: <key content>
type: Opaque
EOF
```

Then, we can use the same custom CA to create the CA Issuer for the `Cert-Manager` Operator, it will sign the end TLS certificate for OpenShift ServiceMesh IngressGateway.

Create a secret containing your custom CA and then the Cert-Manager resources. Fill the resources based on your environment:

```
$ oc -n cert-manager create secret generic ca-key-pair --from-file=tls.key=<CA key> --from-file=tls.crt=<CA certificate>
$ oc create -f cert-manager_manifests/clusterissuer.yaml
$ cp -p cert-manager_manifests/certificate.yaml /tmp/certificate.yaml
$ vi /tmp/certificate.yaml
$ oc create -f /tmp/certificate.yaml
```

The OpenShift ServiceMesh Istio Gateway is already configured for mounting a custom certificate and it's needed to restart the Istio Gateway pod to mount the newly created custom certificate, signed by your custom CA and saved into the secret `istio-ingressgateway-custom-certs`

And finally, let's deploy some workload into the ServiceMesh using the infamous `bookinfo` application.

We will use Kustomize with an inline patch to configure the Azure Traffic Manager DNS name.


```
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mesh-workload
  namespace: openshift-gitops
spec:
  destination:
    namespace: 'bookinfo'
    server: 'https://kubernetes.default.svc'
  source:
    path: mesh_gitops_workload/base
    repoURL: 'https://github.com/agabriel81/terraform-aro.git'
    targetRevision: mtls_tempo
    kustomize:
      patches:
      - target:
          kind: Route
          name: trafficmanager-route
        patch: |-
          - op: replace
            path: /spec/host
            value: $TF_VAR_tm_route
      - target:
          kind: Gateway
          name: bookinfo-gateway
        patch: |-
          - op: replace
            path: /spec/servers/0/hosts/0
            value: $TF_VAR_tm_route
      - target:
          kind: VirtualService
          name: bookinfo
        patch: |-
          - op: replace
            path: /spec/hosts/0
            value: $TF_VAR_tm_route
  project: default
  sources: []
  syncPolicy:
    retry:
      limit: 5
      backoff:
        duration: 15s
        maxDuration: 3m0s
        factor: 2
EOF
```

Access the OpenShift GitOps ArgoCD instance and sync the `mesh-workload` Application.

The repository will configure a passthrough OpenShift Route for exposing our $TF_VAR_tm_route/productpage endpoint, served by an Azure Traffic Manager component.

The application should expose a certificate signed by our custom CA with a 2h duration.

The certificate will be automatically renewed by the OpenShift Cert-Manager Operator



REFERENCE

[1] https://docs.openshift.com/gitops/1.12/understanding_openshift_gitops/about-redhat-openshift-gitops.html

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/traffic_manager_azure_endpoint

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/traffic_manager_external_endpoint

