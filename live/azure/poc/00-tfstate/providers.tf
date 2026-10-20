provider "azurerm" {
  features {}

  # null falls back to ARM_SUBSCRIPTION_ID or the az CLI default subscription.
  subscription_id = var.subscription_id
}
