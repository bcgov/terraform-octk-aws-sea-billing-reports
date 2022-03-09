# <application_license_badge>

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](./LICENSE)

# OCTK AWS SEA Billing Utility

This repo provides tooling to help process billing data from an AWS SEA into more usable forms including monthly
tenant "bills".

## Project Status

- [x] Development
- [ ] Production/Maintenance

## Background

At one point, there were two billing-related utilities contained in this repo. One was based on a step-function/lambda model running in AWS.  The other - which actually used much of the python code from the lambda version - is more of a "classic" script that can be easily run on a developer or admin's local workstation, or (eventually) in a container, as described [here](https://github.com/bcgov/cloud-pathfinder/issues/1068).

The next iteration included a docker runnable billing utility, see below. This avoids storing large report CSVs and other outputs being store locally, and is a step towards [sending automated billing reports via cloudwatch events](https://github.com/bcgov/cloud-pathfinder/issues/1068).

## Getting Started

The current billing utility is contained in the `billing-report-utility` directory. Currently `local` and `Docker` setups are supported.

### Additional Pre-requisites

- The billing utility requires that Athena has been set up to query "Cost and Usage Reports" as described [here](https://docs.aws.amazon.com/cur/latest/userguide/cur-query-athena.html).

- The billing utility uses [Fixer](https://fixer.io/) to calculate exchange rates from UDS to CAD. you will need to get an API key from them and store it in your local environment as `FX_API_KEY`

#### Set up local environment

>Note: The Local Billing Utility is built using python3 and uses several open source libraries. Creating a dedicated `virtualenv` (as described [here](https://docs.python.org/3/library/venv.html) is recommended to avoid conflicts/clashes with other python applications and libraries on your machine.

```shell
$ cd billing-report-utility
$ pip3 install -r requirements.txt
```

#### Set up Docker environment
Build the Docker image from the root directory:
```shell
docker build -t billing-utility .
```

Example docker test run:

```shell
docker run \
-e ARGS="-d true -ro test.email@gov.bc.ca weekly" \
-e AWS_ACCESS_KEY_ID \
-e AWS_SECRET_ACCESS_KEY \
-e AWS_SESSION_TOKEN \
-e AWS_DEFAULT_REGION \
-e FX_API_KEY \
billing-utility
```
- `ARGS` is a string of all arguments described in the "Usage / Options" section below. The example above is a test run where:
  - `-d` (DELIVER) is true so the emails will be sent
  - `-ro` (RECIPIENT_OVERRIDE) is set to `test.email@gov.bc.ca` so it wont be sent to product owners or anyone else
  - `weekly` is the type of run so it will just look at billing reports from a week ago today
- The `AWS_*` vars are from an AWS account with permissions as described in the "Prerequisite" in the "Usage / Options" section below
- `FX_API_KEY` is the key obtained from [Fixer](https://fixer.io/) which provides accurate, current exchange rates
  - Occasionally this free service will go down but this can be circumnavigated by setting the exchange rate from USD to CAD directly using the env var `FX_RATE`

#### Usage / Options

> Prerequisite: The utility requires access to credentials with appropriate permissions to perform all the AWS operations required. The utility accesses credentials using any of the mechanisms supported by `boto3`, the AWS API library it uses.  For example, by using a credentials file, and optionally, the `AWS_PROFILE` environment variable, or by specifying credentials directly via `AWS_*` environment variables set in your shell.  More details/examples are available in the [boto3 docs](https://boto3.amazonaws.com/v1/documentation/api/latest/guide/credentials.html). The specific permission required include reading from the `organizations` API, reading/writing to `s3` buckets, executing `athena` queries, and accessing `ses` APIs to send email.  Ultimately, a purpose-defined role should be created for the purposes of running this script,as described [here](https://github.com/bcgov/cloud-pathfinder/issues/1067).

```shell
usage: billing [-h] [-d DELIVER] [-ro RECIPIENT_OVERRIDE] [-cc CARBON_COPY] [-bgs BILLING_GROUPS] [-ll LOG_LEVEL] [-q QUERY_RESULTS_LOCAL_FILE] {date,dt,weekly,w,billperiod,bp} ...

Processing billing data.

positional arguments:
  {date,dt,weekly,w,billperiod,bp}

optional arguments:
  -h, --help            show this help message and exit
  -d DELIVER, --deliver DELIVER
                        True/False value inidicating whether email delivery should be done.
  -ro RECIPIENT_OVERRIDE, --recipient_override RECIPIENT_OVERRIDE
                        Email address (typically for testing/verification) to which reports will be delivered instead of account admins.
  -cc CARBON_COPY, --carbon_copy CARBON_COPY
                        Email address to which reports will be delivered to, in addition to other recipients.
  -bgs BILLING_GROUPS, --billing_groups BILLING_GROUPS
                        Comma-separated list of billing groups for which to process billing data.
  -ll LOG_LEVEL, --log_level LOG_LEVEL
                        Specify logging level. Example --loglevel debug
  -q QUERY_RESULTS_LOCAL_FILE, --query_results_local_file QUERY_RESULTS_LOCAL_FILE
                        Full path to an existing, query output file in CSV format on the local system. If not specified, an Athena query will be performed, and the query results file will be
                        downloaded to the local system.

```

Running the utility locally will create files in folders structure below, nested within the `billing-report-utility` directory:
- `output/<guid>/query_results/query_results.csv`  # *LARGE* CSV file containing all, fine-grained billing records for specified period
- `output/<guid>/summarized/charges-YYYY-MM-DD-YYYY-DD-MM-ALL.xls`  # Excel file containing summarized billing records for ALL billing groups for specified period
- `output/<guid>/summarized/charges-YYYY-MM-DD-YYYY-DD-MM-<BILLING_GROUP_NAME>.xls`  # Excel files containing summarized billing records (one file for each  BILLING_GROUP) for specified period.
- `output/<guid>/reports/YYYY-MM--DD-YYYY-MM-DD-BILLING_GROUP_NAME.html`  # HTML billing report (pivot table) for each billing group, with charges grouped by account and service.

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
