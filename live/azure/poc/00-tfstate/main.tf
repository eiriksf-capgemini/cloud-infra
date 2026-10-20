# Remote state backend for the azure/poc stacks: one storage account, one container.
#
# Access is Entra ID only (no shared keys). The other stacks use
# `use_azuread_auth = true` in their backend config, so the identity running tofu
# needs "Storage Blob Data Contributor" on this account; we grant it to the deployer.

locals {
  tags = merge({
    environment = "poc"
    managed_by  = "opentofu"
    repo        = "cloud-infra"
    stack       = "azure/poc/00-tfstate"
  }, var.tags)
}

data "azurerm_client_config" "current" {}

locals {
  trusted_egress = [
    for line in split("\n", file("${path.module}/../allowlist/trusted-egress-ipv4.txt")) : trimspace(line)
    if trimspace(line) != "" && !startswith(trimspace(line), "#")
  ]
}

resource "random_id" "suffix" {
  byte_length = 2
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.name_prefix}-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  # 3-24 lowercase alphanumerics, globally unique.
  name                = "st${replace(var.name_prefix, "-", "")}${random_id.suffix.hex}"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  # Source-IP firewall (ADR 0009): only the operators' egress ranges may reach the state
  # blobs; Azure services bypass. ARM operations on the account itself are not affected, so
  # a lockout is fixed with `az storage account network-rule add`.
  dynamic "network_rules" {
    for_each = var.storage_restricted ? [1] : []
    content {
      default_action = "Deny"
      bypass         = ["AzureServices"]
      ip_rules       = distinct(concat(local.trusted_egress, var.storage_extra_sources))
    }
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "deployer_blob_contributor" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Subscription-wide spending guardrail (ADR 0004). Lives here because this stack is
# the one that is never destroyed. Budgets do not stop spending; they only alert.
resource "azurerm_consumption_budget_subscription" "poc" {
  name            = "budget-${var.name_prefix}"
  subscription_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  amount          = var.monthly_budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_roles  = ["Owner"]
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_roles  = ["Owner"]
    contact_emails = var.budget_contact_emails
  }

  lifecycle {
    ignore_changes = [time_period[0].start_date]
  }
}
