# Terraforming a public Azure Red Hat OpenShift (ARO) plus GitOps ServiceMesh

Prerequisites and versions:

```
- Terraform v1.8.3
- az (CLI): 2.60.0
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
$ oc login <API URL> -u kubeadmin -p <password>
```

Access the ARO console and install the OpenShift GitOps using the official documentation [1] (version 1.12 at the time of writing).

Create a GitOps application for installating the Cert-manager, Kiali, Jaeger and ServiceMesh Operators, with ServiceMeshControlPlane and ServiceMeshMemberRoll CRDs pointing the `mesh_gitops_cluster` directory of this repository. 
This process requires `cluster-admin` permissions to the `openshift-gitops-argocd-application-controller` ServiceAccount:

```
$ oc adm policy add-cluster-role-to-user cluster-admin -z openshift-gitops-argocd-application-controller -n openshift-gitops




REFERENCE
[1] https://docs.openshift.com/gitops/1.12/understanding_openshift_gitops/about-redhat-openshift-gitops.html
https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster

