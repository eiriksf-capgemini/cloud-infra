# ADR 0001: Use OpenTofu as the infrastructure-as-code tool

Date: 2026-10-20
Status: Accepted

## Context

This repository is a proof of concept for managing cloud infrastructure as code, starting on
Azure but structured to support AWS and GCP later. HashiCorp relicensed Terraform under the
Business Source License (BSL) in 2023, which rules it out for this project. The alternatives
considered were OpenTofu, Pulumi, Ansible and Crossplane.

## Decision

Use **OpenTofu** (Linux Foundation, MPL 2.0). Plain stacks, no Terragrunt for now.

## Rationale

- Drop-in fork of Terraform: same HCL, same provider ecosystem (`azurerm`, `aws`, `google`,
  `helm`, `kubernetes`). Skills transfer directly to any Terraform codebase.
- Largest community and module ecosystem of the options.
- Declarative plan/apply model with state is the right fit for provisioning cloud resources.
- Terragrunt was deferred: with four stacks a shared `backend.hcl` and a Makefile are enough.
  Revisit if `live/` grows past roughly six stacks or a second environment appears.

## Alternatives rejected

- **Pulumi** (Apache 2.0): strong option, real programming languages, bridged Terraform
  providers give equal coverage. Rejected because the goal is familiarity with mainstream IaC;
  HCL is the lingua franca.
- **Ansible**: configuration management. No plan or state model, so drift detection and safe
  destroy are weak for cloud resources.
- **Crossplane**: Kubernetes-native and attractive for multi-cloud, but it needs a cluster
  before it can create one. Candidate for a later in-cluster experiment via GitOps.

## Consequences

- `tofu` is the only CLI needed for provisioning. Pinned in `.tool-versions`.
- The `terraform {}` block name is kept in HCL for provider compatibility; this is expected.
