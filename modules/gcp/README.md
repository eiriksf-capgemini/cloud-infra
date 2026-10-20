# modules/gcp (placeholder)

Not implemented yet. When GCP is added, create:

- `modules/gcp/network` – VPC, subnet with secondary ranges for pods/services, Cloud NAT.
- `modules/gcp/gke` – GKE cluster (Autopilot or Standard) implementing the common cluster
  interface from ADR 0002 with the same inputs/outputs as `modules/azure/aks`.

Then add `live/gcp/poc/{00-tfstate,10-network,20-cluster,30-gitops}` (GCS backend) and
`gitops/clusters/gcp-poc/`. `modules/k8s/*` is reused unchanged.
