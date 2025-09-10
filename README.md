# Terraforming a public Azure Red Hat OpenShift (ARO) cluster, install OpenShift ServiceMesh using OpenShift GitOps with custom CA for ServiceMesh workload by Cert-Manager Operator

Prerequisites and versions:

```
- Terraform (CLI): v1.9.2
- az (CLI): 2.62.0
- oc (CLI): version depend on the cluster version
```
```
- ARO: 4.17
```

Clone the repository and change to repo directory:
```
$ git clone https://github.com/agabriel81/terraform-aro.git
$ cd terraform-aro/terraform-code
```

Start the Terraform process by passing few variables:
```
$ export TF_VAR_pull_secret='{"auths":{"arosvc.azurecr.io....'
$ export TF_VAR_azure_app_name=agabriel-app-aro-eus
$ export TF_VAR_cluster_domain=agabriel-eus
$ export TF_VAR_cluster_version=4.17.27
$ export TF_VAR_location=eastus
$ export TF_VAR_resourcegroup_name=aro-eus-agabriel
$ export TF_VAR_cluster_name=aro-eus-cluster
```

Deploy all Azure and OpenShift resources using Terraform:

```
$ terraform init
$ terraform validate
$ terraform plan 
$ terraform apply 
```

After completing the installation, all the Azure requirements will be created, including the StorageAccount and the Container which will be used for the TempoStack configuration.
Let's retrieve ARO credentials, ARO console and ARO API URL:

```
$ az aro list-credentials --name ${TF_VAR_cluster_name} --resource-group ${TF_VAR_resourcegroup_name}
$ az aro show --name ${TF_VAR_cluster_name} --resource-group ${TF_VAR_resourcegroup_name} --query "consoleProfile.url" -o tsv
$ az aro show -g ${TF_VAR_resourcegroup_name} -n ${TF_VAR_cluster_name} --query apiserverProfile.url -o tsv 
$ oc login $(az aro show -g ${TF_VAR_resourcegroup_name} -n ${TF_VAR_cluster_name} --query apiserverProfile.url -o tsv) -u kubeadmin
```


REFERENCE

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/traffic_manager_azure_endpoint

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/traffic_manager_external_endpoint

