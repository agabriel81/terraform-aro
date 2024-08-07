# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.102.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "=2.48.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  skip_provider_registration = true # This is only required when the User, Service Principal, or Identity running Terraform lacks the permissions to register Azure Resource Providers.
  features {}
}

provider "azuread" {
  tenant_id = "64dc69e4-d083-49fc-9569-ebece1dd1408"
}
