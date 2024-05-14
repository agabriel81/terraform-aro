variable "location" {
  type = string
}

variable "azure_app_name" {
  type = string
}

variable "resourcegroup_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vnet_name" {
  type = string
  default = "aro-vnet"
}

variable "master_subnet_name" {
  type = string
  default = "aro-vnet-master"
}

variable "worker_subnet_name" {
  type = string
  default = "aro-vnet-worker"
}

variable "pull_secret" {
    type = string
}

variable "cluster_domain" {
    type = string
}

variable "cluster_version" {
    type = string
}

variable "tm_route" {
    type = string
}
