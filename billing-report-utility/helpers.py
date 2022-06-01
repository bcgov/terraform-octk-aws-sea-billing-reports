import logging
import os
import sys
import re

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
logger.addHandler(handler)


def get_sts_credentials(role_to_assume, aws_region, sts_endpoint, role_session_name):

    # Assume cross account role needed to perform org level  account queries
    logger.info(f"Assuming role: {role_to_assume}")
    sts_client = boto3.client(
        'sts',
        region_name=aws_region,
        endpoint_url=sts_endpoint
    )

    try:
        assumed_role_object = sts_client.assume_role(
            DurationSeconds=3600,
            RoleArn=role_to_assume,
            RoleSessionName=role_session_name
        )
    except ClientError as err:
        if err.response["Error"]:
            logger.error("STS Assume Role Error: ", err)
        return err

    logger.info(f"Successfully assumed role: {role_to_assume}")

    # From the response that contains the assumed role, get the temporary
    # credentials that can be used to make subsequent API calls
    return assumed_role_object['Credentials']


def get_account_name_element(account_details, element_index):
    account_email = account_details['email']
    account_name = account_details['name']
    if re.search("app", account_email):
        return account_name.split("-")[element_index]
    else:
        return account_name


def query_org_accounts():
    query_org_account_role_to_assume = os.environ["QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN"]
    sts_endpoint = "https://sts.ca-central-1.amazonaws.com"
    role_session_name = "QueryOrgAccounts"

    if os.environ['AWS_DEFAULT_REGION']:
        aws_default_region = os.environ['AWS_DEFAULT_REGION']
    else:
        aws_default_region = "ca-central-1"

    credentials = get_sts_credentials(
        query_org_account_role_to_assume, aws_default_region,
        sts_endpoint, role_session_name
    )

    try:
        org_client = boto3.client(
            'organizations',
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken'],
        )
    except ClientError as err:
        logger.error(f"A boto3 client error has occurred: {err}")
        return err


    # we have lots of accounts - use a Paginator
    paginator = org_client.get_paginator('list_accounts')
    page_iterator = paginator.paginate()

    core_billing_group_tags = {
        "billing_group": "SEA Core",
        "admin_contact_email": "julian.subda@gov.bc.ca",
        "admin_contact_name": "Julian Subda",
        "Project": "Landing Zone Core",
        "Environment": "Core"
    }

    accounts = []
    for page in page_iterator:
        for account in page['Accounts']:
            tags_response = org_client.list_tags_for_resource(
                ResourceId=account['Id']
            )
            transposed_tags = {}
            for tag in tags_response['Tags']:
                transposed_tag = {
                    tag['Key']: tag['Value']
                }
                transposed_tags.update(transposed_tag)

            account_details = {
                "arn": account['Arn'],
                "email": account['Email'],
                "id": account['Id'],
                "name": account['Name'],
                "status": account['Status']
            }

            account_details.update(transposed_tags)

            if not transposed_tags.get('billing_group', None):
                logger.debug(f"Account '{account_details['id']}' missing metadata tags; applying defaults.")
                account_details.update(core_billing_group_tags)

            account_details['license_plate'] = get_account_name_element(account_details, 0)
            accounts.append(account_details)

    return accounts
