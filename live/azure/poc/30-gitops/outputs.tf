output "argocd_namespace" {
  value = module.argocd.namespace
}

output "port_forward_command" {
  value = module.argocd.port_forward_command
}

output "initial_admin_password_command" {
  value = module.argocd.initial_admin_password_command
}
