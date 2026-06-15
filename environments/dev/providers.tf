terraform {
  required_version = ">= 1.9"

  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }

  # Replace with your actual Azure Storage backend details.
  # Run: az storage account create ... before first use.
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stfabrictfstate"     # must be globally unique
    container_name       = "tfstate"
    key                  = "fabric/dev/terraform.tfstate"
  }
}

provider "fabric" {
  # Auth is picked up from the environment:
  #   FABRIC_TENANT_ID, FABRIC_CLIENT_ID, FABRIC_CLIENT_SECRET  (service principal)
  #   or az login / AZURE_* env vars for interactive/CLI auth
}

provider "azuread" {
  # Auth is picked up from the environment:
  #   ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET  (service principal)
  #   or az login for interactive auth
}
