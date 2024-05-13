# Terraforming Azure Red Hat OpenShift (ARO) plus GitOps ServiceMesh

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

For example

```
$ terraform init
$ terraform validate
$ terraform plan --var 'pull_secret={"auths":{"arosvc.azurecr.io".....' --var 'cluster_domain=<your cluster domain>' --var 'cluster_version=<your cluster version>' --var 'location=<your cluster location>' --var 'resourcegroup_name=<your cluster resource group>' --var 'cluster_name=<your cluster name>'
$ terraform apply --var 'pull_secret={"auths":{"arosvc.azurecr.io".....' --var 'cluster_domain=agabriel-ger' --var 'cluster_version=4.12.25' --var 'location=germanywestcentral' --var 'resourcegroup_name=aro-ger-agabriel' --var 'cluster_name=aro-ger-cluster1'
```


REFERENCE
```
https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster
```
