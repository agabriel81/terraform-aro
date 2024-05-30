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
  name                 = "AppGatewaySubnet"
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = ["10.0.3.0/27"]
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
  aro_default_ingress_ip         = "${azurerm_redhat_openshift_cluster.aro-cluster.ingress_profile[0].ip_address}"
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
    ip_addresses = [local.aro_default_ingress_ip]
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/"
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

//resource "azurerm_subnet" "bastion_subnet" {
//  name                 = "AzureBastionSubnet"
//  resource_group_name  = azurerm_resource_group.aro_rg.name
//  virtual_network_name = azurerm_virtual_network.aro_vnet.name
//  service_endpoints    = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
//  address_prefixes     = ["10.0.2.0/27"]
//}

//resource "azurerm_public_ip" "bastion_pip" {
//  name                = "bastion-pip"
//  location            = azurerm_resource_group.aro_rg.location
//  resource_group_name = azurerm_resource_group.aro_rg.name
//  allocation_method   = "Static"
//  sku                 = "Standard"
//}

//resource "azurerm_bastion_host" "bastion_aro" {
//  name                = "bastion-aro"
//  location            = azurerm_resource_group.aro_rg.location
//  resource_group_name = azurerm_resource_group.aro_rg.name

//  sku                 = "Standard"
//  ip_connect_enabled  = "true"
//  tunneling_enabled   = "true"

//  ip_configuration {
//    name                 = "configuration"
//    subnet_id            = azurerm_subnet.bastion_subnet.id
//    public_ip_address_id = azurerm_public_ip.bastion_pip.id
//  }
//}

resource "azurerm_traffic_manager_profile" "aro_tm" {
  name = "agabriel-aro-tm"
  resource_group_name    = azurerm_resource_group.aro_rg.name
  traffic_routing_method = "Weighted"

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

resource "azurerm_traffic_manager_azure_endpoint" "aro-tm-endpoint" {
  name                 = var.cluster_name
  profile_id           = azurerm_traffic_manager_profile.aro_tm.id
  always_serve_enabled = false
  weight               = 50
  target_resource_id   = azurerm_public_ip.appgw_pip.id
}

resource "azurerm_network_interface" "jumphost_nic" {
  name                = "jumphost-nic"
  location            = azurerm_resource_group.aro_rg.location
  resource_group_name = azurerm_resource_group.aro_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main_subnet.id
    private_ip_address_allocation = "Static"
  }
}

resource "azurerm_linux_virtual_machine" "jumphost" {
  name                = "jumphost"
  resource_group_name = azurerm_resource_group.aro_rg.name
  location            = azurerm_resource_group.aro_rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.jumphost_nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa_aro.pub")
  }


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "8-lvm-gen2"
    version   = "latest"
  }
}

output "console_url" {
  value = azurerm_redhat_openshift_cluster.aro-cluster.console_url
}

