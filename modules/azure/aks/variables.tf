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
    vm_size    = optional(string, "Standard_B2s_v2") # 2 vCPU / 8 GB burstable, Intel; the AMD twin B2as_v2 hit AllocationFailed in the region (ADR 0004)
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

variable "workload_identity_enabled" {
  description = "Run the Entra Workload ID mutating webhook (azure-wi-webhook, 2 replicas x 100m CPU). Only needed once a pod uses azure.workload.identity/use. The OIDC issuer stays on regardless, so turning this on later is an in-place update (ADR 0004)."
  type        = bool
  default     = true
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the API server endpoint (kubectl, Argo CD CLI, CI). [] = reachable from anywhere (Entra ID still required). Max 200. Recovery if locked out: az aks update --api-server-authorized-ip-ranges."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.api_server_authorized_ip_ranges) <= 200
    error_message = "api_server_authorized_ip_ranges: AKS accepts at most 200 ranges."
  }

  validation {
    condition     = alltrue([for s in var.api_server_authorized_ip_ranges : can(cidrhost(s, 0))])
    error_message = "api_server_authorized_ip_ranges entries must be CIDRs (a single host is x.x.x.x/32)."
  }
}

variable "azure_monitor_metrics_enabled" {
  description = "Enable the Azure Monitor metrics add-on (ama-metrics) that scrapes Prometheus metrics. Needs a destination from modules/azure/managed-prometheus; see ADR 0008. Costs ~300-500 MiB of node memory."
  type        = bool
  default     = false
}

variable "azure_monitor_metrics_annotations_allowed" {
  description = "Comma-separated Kubernetes annotation keys exported as labels on kube_*_annotations metrics. null = none."
  type        = string
  default     = null
}

variable "azure_monitor_metrics_labels_allowed" {
  description = "Comma-separated Kubernetes label keys exported as labels on kube_*_labels metrics. null = none."
  type        = string
  default     = null
}
