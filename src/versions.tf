terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~>0.11"
    }
  }
}

provider "azurerm" {
  features {
    # Due to Storage Account network_rules
    storage {
      data_plane_available = false
    }
  }
}
