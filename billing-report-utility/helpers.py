import logging
import sys
import re
import boto3

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
logger.addHandler(handler)


def get_account_name_element(account_details, element_index):
    account_email = account_details['email']
    account_name = account_details['name']
    if re.search("app", account_email):
        return account_name.split("-")[element_index]
    else:
        return account_name


def query_org_accounts():
    org_client = boto3.client('organizations')

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
