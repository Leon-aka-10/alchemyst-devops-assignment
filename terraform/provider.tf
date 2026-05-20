terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstatealchemyst"
    container_name       = "tfstate"
    key                  = "assignment.tfstate"
    # Auth via ARM_ACCESS_KEY env var — no service principal needed
  }
}

provider "azurerm" {
  features {}
  # Inherits CLI auth token from az login step in pipeline
  # No client_id or client_secret — student AD tenant blocks SP creation
  subscription_id = "3088b175-92ef-4dd7-9020-ee7ae696fd1a"
  tenant_id       = "5fe78ac1-1afe-4009-aa04-a71efb4a5042"
}