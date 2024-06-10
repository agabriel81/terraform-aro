# Terraforming a private Azure Red Hat OpenShift (ARO) cluster, install OpenShift ServiceMesh control-plane and data-plane, update Azure resources using Ansible

Prerequisites and versions:

```
- Terraform (CLI): v1.8.3
- az (CLI): 2.60.0
- oc (CLI): version depend on the cluster version
- a public ssh key in the file `~/.ssh/id_rsa_aro.pub` for accessing the jumphost
```
```
- ARO: 4.13
- OpenShift GitOps: 1.12
- OpenShift Kiali: 1.73
- OpenShift Jaeger: 1.53
- OpenShift ServiceMesh: 2.5
- OpenShift Cert-Manager: 1.12
```

Clone the repository and change to repo directory:
```
$ https://github.com/agabriel81/terraform-aro.git
$ cd terraform-aro/terraform-code
```

Start the Terraform process by passing few variables:
```
$ export TF_VAR_pull_secret='{"auths":{"arosvc.azurecr.io....'
$ export TF_VAR_cluster_domain=agabriel-ger
$ export TF_VAR_cluster_version=4.13.26
$ export TF_VAR_location=germanywestcentral
$ export TF_VAR_resourcegroup_name=aro-ger-agabriel
$ export TF_VAR_cluster_name=aro-ger-cluster
```

Check if you want to override any variable (VNET, master/worker subnet name and CIDR etc) using the `override.tf_to_be_implemented` example file (by renaming it `override.tf`)

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

From a configured Ansible Controller (ansible-core, python, Ansible collection installed etc), launch the `ansible/playbook.yaml` playbook.
Clone this repository and update `ansible.cfg` data with your Ansible Hub token to complete the Ansible Controller configuration.
A `custom_data` content was deployed in the `jumphost` host in the file `/var/lib/cloud/instance/scripts/part-001`, it's possible to review it and complete the configuration of the Ansbile Controller.

Make sure to create an Ansible Vault into the file `openshift_passwords.yml` hosting the `admin` (kubeadmin for example) password for the OpenShift Cluster.

```
$ ansible-vault create openshift_password.yml
[...]
openshift_admin_password: <your password>
$ ansible-playbook ansible/playbook.yaml
```

The Ansible playbook will configure ARO required Operators and deploy a sample application.
Review the `var_files.yaml` matching your ARO resources.

```
$ cd terraform-aro/ansible/vars
$ vi var_files.yaml
```

Start the Ansible Playbook:

```
$ cd terraform-aro/ansible
$ ansible-playbook --vault-id @prompt playbook.yaml
```








REFERENCE

https://registry.terraform.io/providers/hashicorp/azurerm/3.102.0/docs/resources/redhat_openshift_cluster
