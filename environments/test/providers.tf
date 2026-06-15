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

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stfabrictfstate"
    container_name       = "tfstate"
    key                  = "fabric/test/terraform.tfstate"
  }
}

provider "fabric" {}
provider "azuread" {}
