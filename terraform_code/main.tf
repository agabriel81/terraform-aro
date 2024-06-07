# since these variables are re-used - a locals block makes this more maintainable
locals {
  app_gw_pip                     = "${var.cluster_name}-appgw-pip"
  aro_app_name                   = "${var.cluster_name}-app"
  aro_vnet_name                  = "${var.cluster_name}-vnet"
  jumphost_name                  = "${var.cluster_name}-jumphost"
  aro_custom_domain              = "${var.cluster_name}.openshift.internal"
  aro_master_subnet_name         = "${var.master_subnet}-${var.cluster_name}"
  aro_worker_subnet_name         = "${var.worker_subnet}-${var.cluster_name}"
  aro_master_subnet_cidr         = "${var.master_subnet_cidr}"
  aro_worker_subnet_cidr         = "${var.worker_subnet_cidr}"
  aro_vnet_cidr                  = "${var.vnet_cidr}"
  aro_vnet_link                  " "${var.cluster_name}-private-dns-link"
  app_gw_cidr                    = "${var.app_gw_cidr}"
  app_gw_name                    = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-appgw"
  backend_address_pool_name      = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-beap"
  frontend_port_name             = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-feport"
  frontend_ip_configuration_name = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-feip"
  http_setting_name              = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-be-htst"
  listener_name                  = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-httplstn"
  request_routing_rule_name      = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-rqrt"
  redirect_configuration_name    = "${azurerm_redhat_openshift_cluster.aro_cluster.name}-rdrcfg"
  aro_default_ingress_ip         = "${azurerm_redhat_openshift_cluster.aro_cluster.ingress_profile[0].ip_address}"
}

data "azurerm_client_config" "azurerm_client" {}

data "azuread_client_config" "azuread_client" {}

resource "azuread_application_registration" "azuread_app" {
  display_name = local.aro_app_name
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
  name                = local.aro_vnet_name
  address_space       = [local.aro_vnet_cidr]
  location            = var.location
  resource_group_name = azurerm_resource_group.aro_rg.name
}

resource "azurerm_subnet" "master_subnet" {
  name                 = local.aro_master_subnet_name
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = [local.aro_master_subnet_cidr]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "worker_subnet" {
  name                 = local.aro_worker_subnet_name
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = [local.aro_worker_subnet_cidr]
  service_endpoints    = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
}

resource "azurerm_redhat_openshift_cluster" "aro_cluster" {
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
    subnet_id = azurerm_subnet.master_subnet.id
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

resource "azurerm_private_dns_zone" "aro_custom_domain" {
  name                = local.aro_custom_domain
  resource_group_name = azurerm_resource_group.aro_rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "aro_custom_domain_vnet_link" {
  name                  = local.aro_vnet_link
  resource_group_name   = azurerm_resource_group.aro_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.aro_custom_domain.name
  virtual_network_id    = azurerm_virtual_network.aro_vnet.id
}

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "AppGatewaySubnet"
  resource_group_name  = azurerm_resource_group.aro_rg.name
  virtual_network_name = azurerm_virtual_network.aro_vnet.name
  address_prefixes     = [local.app_gw_cidr]
}

resource "azurerm_public_ip" "appgw_pip" {
  name                = local.app_gw_pip
  resource_group_name = azurerm_resource_group.aro_rg.name
  location            = azurerm_resource_group.aro_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1","2","3"]
  domain_name_label   = var.cluster_name
}

resource "azurerm_application_gateway" "aro_appgw" {
  name                = local.app_gw_name
  resource_group_name = azurerm_resource_group.aro_rg.name
  location            = azurerm_resource_group.aro_rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 3
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
    host_name             = azurerm_public_ip.appgw_pip.fqdn
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

resource "azurerm_network_interface" "jumphost_nic" {
  name                = local.jumphost_name
  location            = azurerm_resource_group.aro_rg.location
  resource_group_name = azurerm_resource_group.aro_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.master_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "jumphost" {
  name                = local.jumphost_name
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
  value = azurerm_redhat_openshift_cluster.aro_cluster.console_url
}

