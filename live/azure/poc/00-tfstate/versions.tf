terraform {
  required_version = ">= 1.8"

  # Intentionally local state: this stack creates the remote backend everyone
  # else uses. Keep terraform.tfstate for this directory safe (it is gitignored);
  # if lost, the resources can be re-imported by name.

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
