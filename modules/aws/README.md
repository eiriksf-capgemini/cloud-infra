# modules/aws (placeholder)

Not implemented yet. When AWS is added, create:

- `modules/aws/network` – VPC, private/public subnets, NAT. Outputs mirror `modules/azure/network`.
- `modules/aws/eks` – EKS cluster implementing the common cluster interface from ADR 0002:
  inputs `name`, `location` (region), `kubernetes_version`, `system_node_pool`, `user_node_pools`,
  `tags`; outputs `cluster_name`, `cluster_id`, `cluster_endpoint`, `cluster_ca_certificate`,
  `oidc_issuer_url`.

Then add `live/aws/poc/{00-tfstate,10-network,20-cluster,30-gitops}` (S3 + DynamoDB or S3
lockfile backend) and `gitops/clusters/aws-poc/`. `modules/k8s/*` is reused unchanged.
