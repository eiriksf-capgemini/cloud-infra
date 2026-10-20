output "automation_account_name" {
  value = azurerm_automation_account.this.name
}

output "stop_schedule" {
  value = "daily at ${var.stop_time} ${var.timezone}"
}

output "start_schedule" {
  value = var.start_time == null ? "manual only (make aks-start)" : "${join("/", var.start_week_days)} at ${var.start_time} ${var.timezone}"
}
