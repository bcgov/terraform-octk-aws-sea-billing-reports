<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~>4.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_management-account"></a> [management-account](#module\_management-account) | ./management-account | n/a |
| <a name="module_operations-account"></a> [operations-account](#module\_operations-account) | ./operations-account | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_mgmt_account_id"></a> [mgmt\_account\_id](#input\_mgmt\_account\_id) | The AWS account ID for the management account. | `any` | n/a | yes |
| <a name="input_mgmt_account_phase1_bucket_suffix"></a> [mgmt\_account\_phase1\_bucket\_suffix](#input\_mgmt\_account\_phase1\_bucket\_suffix) | The suffix for the phase1 bucket in the management account. | `any` | n/a | yes |
| <a name="input_ops_account_id"></a> [ops\_account\_id](#input\_ops\_account\_id) | The AWS account ID for the operations account. | `any` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->