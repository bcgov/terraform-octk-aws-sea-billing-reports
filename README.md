[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)

# OCTK AWS SEA Billing Utility
This repo contains tooling used by the Cloud Pathfinder team to generate and send AWS ECF billing reports.

## Project Status

- [x] Development
- [ ] Production/Maintenance

## Background

The current iteration is based off an earlier solution that leveraged Docker. That version required AWS ECF management account admin privileges and relied on  manual execution on an admin/developer workstation. Arguments were managed by argparse. The solution was cumbersome and did not provide a reliable way to produce weekly, monthly and quarterly reports. A rough sketch of how the solution looked is presented below:

![Previous State](./docs/figs/png/billing_utility_previous_state.drawio.png)

In line with ticket [1068](https://github.com/bcgov/cloud-pathfinder/issues/1068), the solution was ported to run on AWS ECS Fargate. Weekly, monthly and quarterly report generation are now managed by EventBridge. Input arguments that were initially managed by argparse are now supplied by EventBridge as environment variables.

The revised solution still supports generating billing reports for time ranges outside the last billing fiscal (weekly, monthly and quarterly) periods.

## High Level Overview
### AWS Services Used
- Amazon Athena
- Amazon EventBridge
- Amazon Glue
- AWS Elastic Container Repository (ECR)
- AWS Elastic Container Service (ECS)
- Amazon Simple Storage Service (S3)
- Amazon Simple Email Service (SES)

Resources for the current solution is split between the ECF operations and management accounts. Raw billing data is located within an S3 bucket in the ECF management account. Compute operations are performed by resources deployed to the operations account. AWS Glue crawler populates a data catalog in the management account. Athena queries initiated by resources deployed in the operations account extracts raw billing data for a specified date range. This information is saved for further processing in an S3 bucket within the management account.

![Current State](./docs/figs/png/billing_utility_current_state.drawio.png)

Further improvements would involve moving Glue and Athena components from the management account to the operations account. In this approach, cross account replication of the `pbmmaccel-master-phase1` S3 bucket would have billing data available in the operations account. At the time of this writing, the `pbmmaccel-master-phase1` bucket size delta month-over-month is no greater than 50GB.

![Preferred State](./docs/figs/png/billing_utility_preferred_state.drawio.png)


## Getting Started
Resources used in the current iteration of this solution are located in three directories:
- **management-account-terraform-resources**: Terraform resources that deployed to the ECF management account. Contains:
  - Glue resources (Crawler and Data Catalog)
  - Role needed to query org accounts
  - Role needed to perform Athena queries against `pbmmaccel-master-phase1`
  - Customer Managed Key (CMK) used to encrypt data
- **operations-account-terraform-resources:** Terraform resources that deployed to the ECF operations account. Contains:
  - Container related resources: ECR, ECS, Fargate and roles
  - Amazon EventBridge resources
  - Data needed for manual runs from local machine. Stored in Parameter Store
- **billing-report-utility:** Python code used by the utility


### Pending Items
- [ ] Conversion rate from USD to CAD is provided by [Fixer](https://fixer.io/). We're on the free tier which has no uptime or availability guarantees. The service needs to be revised to something more robust. This is set to be addressed by ticket [1727](https://github.com/bcgov/cloud-pathfinder/issues/1727).
- [ ] Monitoring and Alerting: email, container


### Generating reports for dates not handled by EventBridge
Python code contained in the `billing-report-utility` directory can be executed locally to generate billing reports for arbitrary date periods. Several environment variables and permissions are needed in order to do so. The required environment variables can be obtained from the parameter store: `/bcgov/billingutility/manual_run/env_vars` located in the corresponding ECF LZ Operations account. These are as follows:

```shell
REPORT_TYPE="Manual"
START_DATE="<YYYY, M, D>" - eg: "2022, 4, 12"
END_DATE="<YYYY, M, D>" - eg: "2022, 4, 26"
DELIVER="True|False" # Currently not used. Placeholder for future use
RECIPIENT_OVERRIDE="hello.123@localhost" # Currently not used. Placeholder for future use
ATHENA_QUERY_ROLE_TO_ASSUME_ARN="arn:aws:iam::<LZ#-ManagementAccountID>:role/BCGov-Athena-Cost-and-Usage-Report"
ATHENA_QUERY_DATABASE="athenacurcfn_cost_and_usage_report"
QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN="arn:aws:iam::<LZ#-ManagementAccountID>:role/BCGov-Query-Org-Accounts"
ATHENA_QUERY_OUTPUT_BUCKET="bcgov-ecf-billing-reports-output-<LZ#-ManagementAccountID>-ca-central-1"
ATHENA_QUERY_OUTPUT_BUCKET_ARN="arn:aws:s3:::bcgov-ecf-billing-reports-output-<LZ#-ManagementAccountID>-ca-central-1"
CMK_SSE_KMS_ALIAS="arn:aws:kms:ca-central-1:<LZ#-ManagementAccountID>:alias/BCGov-BillingReports"
```
> Note: Running the Python code locally requires several open source libraries. Creating a dedicated `virtualenv` as described [here](https://docs.python.org/3/library/venv.html) is recommended to avoid conflicts/clashes with other Python applications and libraries on your machine.

```shell
$ cd billing-report-utility
$ pip3 install -r requirements.txt
```
Given SES resources are deployed in the ECF LZ operations accounts, you'd need a role in that account to execute the Python script locally. At the time of this writing, the admin role on the operator account is sufficient.

> For local execution, the ECF LZ operations account role must be able to use the CMK corresponding associated with the environment variable: `CMK_SSE_KMS_ALIAS` and also assume corresponding roles associated with environment variables `QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN` and `ATHENA_QUERY_ROLE_TO_ASSUME_ARN`. These are resources deployed in the ECF LZ management account. At the time of this writing, the admin role on the operator account is sufficient. As we scale back on permissions, this will likely be revised further.  

Once the appropriate values as indicated above are available, you can easily run the script using the command:

```shell
python3 billing.py
```
Running the utility locally will create files in folders structure below, nested within the `billing-report-utility` directory:
- `output/<guid>/query_results/query_results.csv`  # *LARGE* CSV file containing all, fine-grained billing records for specified period
- `output/<guid>/summarized/charges-YYYY-MM-DD-YYYY-DD-MM-ALL.xls`  # Excel file containing summarized billing records for ALL billing groups for specified period
- `output/<guid>/summarized/charges-YYYY-MM-DD-YYYY-DD-MM-<BILLING_GROUP_NAME>.xls`  # Excel files containing summarized billing records (one file for each  BILLING_GROUP) for specified period.
- `output/<guid>/reports/YYYY-MM--DD-YYYY-MM-DD-BILLING_GROUP_NAME.html`  # HTML billing report (pivot table) for each billing group, with charges grouped by account and service.

### References/Useful Resources
- [Querying Cost and Usage Reports using Amazon Athena](https://docs.aws.amazon.com/cur/latest/userguide/cur-query-athena.html).

## Getting Help or Reporting an Issue

<!--- Example below, modify accordingly --->
To report bugs/issues/feature requests, please file an [issue](../../issues).

## How to Contribute

<!--- Example below, modify accordingly --->
If you would like to contribute, please see our [CONTRIBUTING](./CONTRIBUTING.md) guidelines.

Please note that this project is released with a [Contributor Code of Conduct](./CODE_OF_CONDUCT.md). By participating
in this project you agree to abide by its terms.

## License

    Copyright 2018 Province of British Columbia

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
