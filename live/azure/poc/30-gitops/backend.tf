terraform {
  backend "azurerm" {
    key = "azure/poc/30-gitops.tfstate"
  }
}
