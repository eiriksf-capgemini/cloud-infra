output "namespace" {
  description = "Namespace Argo CD was installed into."
  value       = helm_release.argocd.namespace
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.argocd.name
}

output "chart_version" {
  description = "Installed argo-cd chart version."
  value       = helm_release.argocd.version
}

output "initial_admin_password_command" {
  description = "Command to fetch the generated admin password."
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "port_forward_command" {
  description = "Command to reach the UI locally at https://localhost:8080"
  value       = "kubectl -n ${var.namespace} port-forward svc/argocd-server 8080:443"
}
