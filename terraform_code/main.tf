data "azurerm_client_config" "azurerm_client" {}

data "azuread_client_config" "azuread_client" {}

resource "azuread_application_registration" "azuread_app" {
  display_name = var.azure_app_name
}

resource "azuread_service_principal" "azuread_sp" {
  client_id = azuread_application_registration.azuread_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.azuread_client.object_id]
}

resource "azuread_service_principal_password" "azuread_sp_pwd" {
  service_principal_id = azuread_service_principal.azuread_sp.object_id
  end_date             = "2024-12-31T23:59:59Z"     
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
  address_prefixes     = ["10.0.0.0/24"]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "worker_subnet" {
  name                 = var.worker_subnet_name
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
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
    visibility = "Private"
  }

  ingress_profile {
    visibility = "Private"
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

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_public_ip" "appgw_pip" {
  name                = "appgw-pip"
  resource_group_name = azurerm_resource_group.aro_rg.name
  location            = azurerm_resource_group.aro_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1","2","3"]
}

# since these variables are re-used - a locals block makes this more maintainable
locals {
  backend_address_pool_name      = "${azurerm_virtual_network.aro_vnet.name}-beap"
  frontend_port_name             = "${azurerm_virtual_network.aro_vnet.name}-feport"
  frontend_ip_configuration_name = "${azurerm_virtual_network.aro_vnet.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.aro_vnet.name}-be-htst"
  listener_name                  = "${azurerm_virtual_network.aro_vnet.name}-httplstn"
  request_routing_rule_name      = "${azurerm_virtual_network.aro_vnet.name}-rqrt"
  redirect_configuration_name    = "${azurerm_virtual_network.aro_vnet.name}-rdrcfg"
  ip_addresses                   = "${azurerm_redhat_openshift_cluster.aro-cluster.ingress_profile[0].ip_address}-ingressip"
}

resource "azurerm_application_gateway" "aro_appgw" {
  name                = "aro-appgw"
  resource_group_name = azurerm_resource_group.aro_rg.name
  location            = azurerm_resource_group.aro_rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gw-conf"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
//    ip_addresses = local.ip_addresses
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/productpage"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}


output "console_url" {
  value = azurerm_redhat_openshift_cluster.aro-cluster.console_url
}

