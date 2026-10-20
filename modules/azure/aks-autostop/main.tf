# Scheduled stop (and optional start) of an AKS cluster using Azure Automation.
#
# Why Automation and not a GitHub Actions cron: it lives next to the cluster, needs no
# CI secrets, and the free tier (500 job-minutes/month) covers a one-minute job per day
# many times over.
#
# What a stopped cluster still costs: load balancer rules and public IP, managed OS
# disks. What it saves: all node compute, which is the bulk of the bill.
# AKS does not guarantee a cluster stopped for more than 30 days can be started again;
# `tofu destroy` the cluster stack for long breaks.

locals {
  # Schedules must start in the future; anchor to tomorrow at the requested time.
  # start_time is then ignored on later plans so the schedule is not recreated daily.
  tomorrow = formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))
}

resource "azurerm_automation_account" "this" {
  name                = "aa-${var.name}-autostop"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Scoped to the single cluster; grants start/stop (managedClusters/*) and nothing else.
resource "azurerm_role_assignment" "aks_contributor" {
  scope                = var.cluster_id
  role_definition_name = "Azure Kubernetes Service Contributor Role"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}

resource "azurerm_automation_runbook" "power" {
  name                    = "Set-AksClusterPowerState"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  runbook_type            = "PowerShell72"
  log_verbose             = false
  log_progress            = false
  description             = "Stops or starts the AKS cluster via ARM REST."
  content                 = file("${path.module}/runbook.ps1")
  tags                    = var.tags
}

resource "azurerm_automation_schedule" "stop" {
  name                    = "stop-daily-${replace(var.stop_time, ":", "")}"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Day"
  interval                = 1
  timezone                = var.timezone
  start_time              = "${local.tomorrow}T${var.stop_time}:00Z"
  description             = "Stop the cluster every day at ${var.stop_time} ${var.timezone}."

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "stop" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  schedule_name           = azurerm_automation_schedule.stop.name
  runbook_name            = azurerm_automation_runbook.power.name

  parameters = {
    clusterid = var.cluster_id
    action    = "stop"
  }
}

resource "azurerm_automation_schedule" "start" {
  count = var.start_time == null ? 0 : 1

  name                    = "start-weekdays-${replace(var.start_time, ":", "")}"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Week"
  interval                = 1
  week_days               = var.start_week_days
  timezone                = var.timezone
  start_time              = "${local.tomorrow}T${var.start_time}:00Z"
  description             = "Start the cluster on ${join(", ", var.start_week_days)} at ${var.start_time} ${var.timezone}."

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "start" {
  count = var.start_time == null ? 0 : 1

  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  schedule_name           = azurerm_automation_schedule.start[0].name
  runbook_name            = azurerm_automation_runbook.power.name

  parameters = {
    clusterid = var.cluster_id
    action    = "start"
  }
}
