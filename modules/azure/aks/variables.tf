# ---------------------------------------------------------------------------
# Common cluster interface. Keep these names in sync with modules/aws/eks and
# modules/gcp/gke when they are added (see ADR 0002).
# ---------------------------------------------------------------------------

variable "name" {
  description = "Cluster name, e.g. 'aks-cloudinfra-poc'."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor/patch version, e.g. '1.33'. null = AKS default for the region."
  type        = string
  default     = null
}

variable "system_node_pool" {
  description = "System node pool sizing. POC default is one small node that also runs workloads."
  type = object({
    vm_size    = optional(string, "Standard_B2ls_v2") # cheapest x86 size AKS accepts for a system pool (ADR 0004)
    node_count = optional(number, 1)
    os_disk_gb = optional(number, 32) # P4 tier; AKS minimum is 30
  })
  default = {}
}

variable "user_node_pools" {
  description = "Optional user node pools keyed by pool name (<= 12 lowercase alphanumerics)."
  type = map(object({
    vm_size    = string
    node_count = optional(number, 1)
    min_count  = optional(number) # set min/max to enable the cluster autoscaler (min may be 0)
    max_count  = optional(number)
    os_disk_gb = optional(number, 64)
    labels     = optional(map(string), {})
    taints     = optional(list(string), [])
    spot       = optional(bool, false) # Spot VMs: up to ~90% cheaper, can be evicted; Azure adds the spot taint
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Azure-specific inputs
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group to create the cluster in (created by modules/azure/network)."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for cluster nodes (created by modules/azure/network)."
  type        = string
}

variable "sku_tier" {
  description = "AKS control plane tier. 'Free' has no SLA and is fine for a POC."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin through Azure RBAC."
  type        = list(string)
  default     = []
}

variable "grant_deployer_cluster_admin" {
  description = "Give the identity running tofu the 'AKS RBAC Cluster Admin' role so kubectl works right after apply."
  type        = bool
  default     = true
}

variable "local_account_disabled" {
  description = "Disable local (non-Entra) accounts. Keep false for the POC so kube_admin_config is available for bootstrap."
  type        = bool
  default     = false
}

variable "pod_cidr" {
  description = "Pod CIDR for Azure CNI Overlay. Must not overlap the VNet."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the VNet or pod CIDR."
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS IP; must be inside service_cidr."
  type        = string
  default     = "10.0.0.10"
}
