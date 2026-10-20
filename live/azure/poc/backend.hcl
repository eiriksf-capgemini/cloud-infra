# Shared backend settings for every stack in live/azure/poc.
# Filled from `make output STACK=live/azure/poc/00-tfstate` (backend_hcl output).
# Each stack sets its own `key` in its backend.tf.
resource_group_name  = "rg-cloudinfra-poc-tfstate"
storage_account_name = "REPLACE_WITH_00_TFSTATE_OUTPUT"
container_name       = "tfstate"
use_azuread_auth     = true
