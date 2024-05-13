data "azurerm_client_config" "azurerm_client" {}

data "azuread_client_config" "azuread_client" {}

resource "azuread_application_registration" "azuread_app" {
  display_name = "ARO-agabriel"
}

resource "azuread_service_principal" "azuread_sp" {
  client_id = azuread_application_registration.azuread_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.azuread_client.object_id]
}

resource "azuread_service_principal_password" "azuread_sp_pwd" {
  service_principal_id = azuread_service_principal.azuread_sp.object_id
  end_date             = "2025-12-31T23:59:59Z"     
}

data "azuread_service_principal" "redhatopenshift" {
  // This is the Azure Red Hat OpenShift RP service principal id, do NOT delete it
  client_id = "f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875"
}

resource "azurerm_role_assignment" "role_network1" {
  scope                = azurerm_virtual_network.aro_vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.azuread_sp.object_id
}

resource "azurerm_role_assignment" "role_network2" {
  scope                = azurerm_virtual_network.aro_vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.redhatopenshift.object_id
}

resource "azurerm_resource_group" "aro_rg" {
  name     = var.resourcegroup_name
  location = var.location
}

resource "azurerm_virtual_network" "aro_vnet" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/22"]
  location            = var.location
  resource_group_name = azurerm_resource_group.aro_rg.name
}

resource "azurerm_subnet" "main_subnet" {
  name                 = "main-subnet"
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = ["10.0.0.0/23"]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "worker_subnet" {
  name                 = var.worker_subnet_name
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = ["10.0.2.0/23"]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

resource "azurerm_redhat_openshift_cluster" "aro-cluster" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.aro_rg.name

  cluster_profile {
    domain = var.cluster_domain
    version = var.cluster_version
    pull_secret = var.pull_secret
  }

  network_profile {
    pod_cidr     = "10.128.0.0/14"
    service_cidr = "172.30.0.0/16"
  }

  main_profile {
    vm_size   = "Standard_D8s_v3"
    subnet_id = azurerm_subnet.main_subnet.id
  }

  api_server_profile {
    visibility = "Public"
  }

  ingress_profile {
    visibility = "Public"
  }

  worker_profile {
    vm_size      = "Standard_D4s_v3"
    disk_size_gb = 128
    node_count   = 3
    subnet_id    = azurerm_subnet.worker_subnet.id
  }

  service_principal {
    client_id     = azuread_application_registration.azuread_app.client_id
    client_secret = azuread_service_principal_password.azuread_sp_pwd.value
  }

  depends_on = [
    azurerm_role_assignment.role_network1,
    azurerm_role_assignment.role_network2,
  ]
}

resource "azurerm_traffic_manager_profile" "aro-tm" {
  name = "agabriel-aro-tm"
  resource_group_name    = azurerm_resource_group.aro_rg.name
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "agabriel-aro-tm"
    ttl           = 100
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/productpage"
    interval_in_seconds          = 30
    timeout_in_seconds           = 9
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_external_endpoint" "aro-tm-endpoint" {
  name                 = var.cluster_name
  profile_id           = azurerm_traffic_manager_profile.aro-tm.id
  always_serve_enabled = false
  priority             = 1
  target               = azurerm_redhat_openshift_cluster.aro-cluster.ingress_profile.0.ip_address
}

output "console_url" {
  value = azurerm_redhat_openshift_cluster.aro-cluster.console_url
}

