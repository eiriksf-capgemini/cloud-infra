# live/azure/poc/00-tfstate

Creates the remote state backend for the other `azure/poc` stacks. Uses **local state**
itself (chicken and egg); the resulting `terraform.tfstate` is gitignored.

```sh
az login
az account set --subscription <id>
make init  STACK=live/azure/poc/00-tfstate
make apply STACK=live/azure/poc/00-tfstate
make output STACK=live/azure/poc/00-tfstate   # copy backend_hcl into ../backend.hcl
```

Role assignment propagation can take up to a minute; if the next stack's `init` returns
403 on the state blob, wait and retry.
