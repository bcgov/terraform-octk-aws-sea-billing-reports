# <application_license_badge>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)

# OCTK AWS SEA Billing Utiilty

This repo provides tooling to help process billing data from an AWS SEA into more usable forms including monthly
tenant "bills".

## Project Status

- [x] Development
- [ ] Production/Maintenance

## Getting Started

There are two billing-related utilities contained in this repo. One is a set terraform configs contained withing
the `terraform` directory. We'll call this the "cloud" billing utility, since associated code executes *within* the AWS
environment. The other is contained in the `local` directory. We'll call this the "local" billing utility since
associated code executes *locally* on a user's workstation.

### Cloud Billing Utility

The Cloud Billing Utility can be deployed into an AWS SEA's management/root account using terraform as follows:

```shell
$ cd terraform
#populate shell with admin-level IAM credentials prior to running below, or prefix command below with AWS_PROFILE=-...  
$ terraform plan -var-file=variables.tfvars

$ terraform apply -var-file=variables.tfvars
```

Once installed as above, the Cloud Billing Utility can be used as follows to generate billing reports within AWS:

```shell
$ aws stepfunctions start-execution --state-machine-arn arn:aws:states:ca-central-1:<root_account id>:stateMachine:process-cur-workflow --input "$(cat billing_report_input.json)" 
```

#### Input file

The above `billing_report_input_json` file has a format matching the one below.  This file may be produced manually, or using the terraform module at http://github.com/bcdevops/terraform-octk-aws-organization-info-extended.

```json
{
	"month": 2,
	"year": 2021,
	"teams": [
		{
			"accountIds": [
				"123456789",
				"901235234"
			],
			"business_unit": "ABC",
			"contact_email": "abc@gov.bc.ca",
			"contact_name": "Abc Abc"
		},
		{
			"accountIds": [
				"2345678990",
				"5432154321"
			],
			"business_unit": "PQR",
			"contact_email": "pqr@gov.bc.ca",
			"contact_name": "Pqr Pqr"
		}
	]
}
```

#### Output

Running the command above will trigger the execution of a sequence of step functions that will query billing data, process it, and output the processed date in a report form *for each billing* for the month/year specified in the input file.

The output files - a set of HTML reports - can be downloaded using the command below:

```shell
aws s3 cp s3://billing-reports-<root_account_id>/reports/ ./reports –recursive
```


### Local Billing Utility

The Local Utility provides similar functionality to the Cloud Billing Utility but uses a refactored version of the code that is simpler to test and adapt, and somewhat reduces the reliance on native AWS services.  While this version works well for AWS billing, it may also provide a starting point for processing billing data from other sources as well.

#### Set up local environment

>Note: The Local Billing Utility is built using python3 and creating a dedicated `virtualenv` is recommended.

```shell
$ cd local
$ pip install -r requirements.txt
```

#### Usage / Options

> Prerequisite: Prior to running utility, your local shell *must* be populated with IAM credentials that have sufficient permission to read AWS account information via the organization API.  The reason is that the utility requires an account metadata lookup structure and it creates it dynamically on each execution  by using the organizations API.

```shell
usage: billing.py [-h] [-y YEAR] [-m MONTH] [-q QUERY_RESULTS_LOCAL_FILE]

Processing billing data.

optional arguments:
  -h, --help            show this help message and exit
  -y YEAR, --year YEAR  The year for which we are interested in producing billing summary data and reports. If not specified, the current year is assumed.
  -m MONTH, --month MONTH
                        The month in the year (-y/--year) for which we are interested in producing billing suammary data and reports. If not specified, the current month is assumed.
  -q QUERY_RESULTS_LOCAL_FILE, --query_results_local_file QUERY_RESULTS_LOCAL_FILE
                        Full path to an existing, query output file in CSV format on the local system. If not specified, an Athena query will be performed, and the query results file will be
                        downloaded to the local system.
```

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
