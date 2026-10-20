terraform {
  # Partial config: the rest comes from ../backend.hcl via `make init`
  # (tofu init -backend-config=../backend.hcl).
  backend "azurerm" {
    key = "azure/poc/10-network.tfstate"
  }
}
