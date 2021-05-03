import csv
import json
from itertools import groupby

import numpy as np
import pandas as pd
from jinja2 import Environment, FileSystemLoader

from openpyxl import Workbook
from openpyxl.utils.dataframe import dataframe_to_rows


def read_file_into_dataframe(local_file, accounts):
	conver_dict = {'line_item_usage_account_id': str}
	pd.set_option('display.float_format', '${:.2f}'.format)
	df = pd.read_csv(local_file, dtype=conver_dict)

	enhance_with_metadata(df, accounts)

	return df


def enhance_with_metadata(df, accounts):

	account_details_by_account_id = make_account_by_id_lookup(accounts)

	core_billing_group = {
		"billing_group": "SEA Core",
		"contact_email": "julian.subda@gov.bc.ca",
		"contact_name": "Julian Subda",
	}

	# def get_metadata_attribute_value(account_id, attribute_name):
	# 	print(f"Account ID:'{account_id}', Attribute Name: '{attribute_name}'")
	# 	attribute_value = account_details_by_account_id[account_id][attribute_name]
	# 	print(f"Attribute Value: '{attribute_value}'")
	#
	# 	return attribute_value
	#
	# df['Account_Name'] = df['line_item_usage_account_id'].apply(lambda x: get_metadata_attribute_value(x, 'name'))

	# troubleshooting
	# df['Account_Name'] = "account-name"
	# df['License_Plate'] = "xyz123"
	# df['Environment'] = "env"

	df['Billing_Group'] = df['line_item_usage_account_id'].apply(
		lambda x: account_details_by_account_id.get(x, core_billing_group).get('billing_group', core_billing_group['billing_group']))
	df['Owner_Name'] = df['line_item_usage_account_id'].apply(
		lambda x: account_details_by_account_id.get(x, core_billing_group).get('contact_name', core_billing_group['contact_name']))
	df['Owner_Email'] = df['line_item_usage_account_id'].apply(
		lambda x: account_details_by_account_id.get(x, core_billing_group).get('contact_email', core_billing_group['contact_email']))
	df['Account_Name'] = df['line_item_usage_account_id'].apply(
		lambda x: account_details_by_account_id.get(x, core_billing_group).get('name', core_billing_group['name']))
	df['License_Plate'] = df['line_item_usage_account_id'].apply(
		lambda x: account_details_by_account_id.get(x, core_billing_group).get('name', core_billing_group['name']).split("-")[0])
	df['Environment'] = df['line_item_usage_account_id'].apply(
		lambda x: account_details_by_account_id.get(x, core_billing_group).get('name', core_billing_group['name']).split("-")[1])


def make_account_by_id_lookup(accounts):
	# billing_group_index_by_account_id = {}
	team_details_by_account_id = {}

	# print(f"Accounts: {accounts}")

	for account in accounts:
		# print(f"Account: {accounts}")
		team_details_by_account_id[account['id']] = account

	# for team in teams:
	# 	for details in team['account_details']:
	# 		team_details_by_account_id[details['id']] = details

	# for team in teams:
	# 	for account_id in team['accountIds']:
	# 		team_details = team_details_by_account_id[account_id]
	# 		team.update(team_details)
	# 		billing_group_index_by_account_id[account_id] = team

	# print(json.dumps(team_details_by_account_id))

	return team_details_by_account_id


def report(query_results_file, report_output_path, accounts, query_parameters):
	month = query_parameters['end_month']
	year = query_parameters['end_year']

	df = read_file_into_dataframe(query_results_file, accounts)

	core_billing_group = {
		"billing_group": "SEA Core",
		"contact_email": "julian.subda@gov.bc.ca",
		"contact_name": "Julian Subda",
		"name": "NA-NA"
	}

	sorted_accounts = sorted(accounts, key=lambda x: x.get('billing_group', core_billing_group['billing_group']))
	accounts_by_billing_group = groupby(sorted_accounts, key=lambda x: x.get('billing_group', core_billing_group['billing_group']))

	for billing_group, bg_accounts in accounts_by_billing_group:
		account_ids = [account["id"] for account in bg_accounts]

		index = ['year', 'month', 'line_item_usage_account_id', 'Account_Name', 'License_Plate', 'Environment', 'Billing_Group', 'Owner_Name', 'Owner_Email',
				 'line_item_product_code']

		billing_temp = df.query(
			f'year == [{year}] and month == [{month}] and (line_item_usage_account_id in {account_ids})')
		billing = pd.pivot_table(billing_temp,
								 index=index,
								 values=['line_item_blended_cost'], aggfunc=[np.sum], fill_value=0, margins=True,
								 margins_name='Total')

		env = Environment(loader=FileSystemLoader('.'))
		template = env.get_template("report.html")

		template_vars = {
			"title": "AWS Report",
			"pivot_table": billing.to_html(),
			"business_unit": billing_group
		}

		html_out = template.render(template_vars)

		report_name = f"{year}-{month}-{billing_group}.html"
		report_file_name = f"{report_output_path}/{report_name}"

		with open(report_file_name, "w") as text_file:
			text_file.write(html_out)


def aggregate(query_results_file, query_parameters, summary_output_file):
	df = read_file_into_dataframe(query_results_file, query_parameters)

	index = ['year', 'month', 'line_item_usage_account_id', 'Account_Name', 'License_Plate', 'Environment', 'Billing_Group', 'Owner_Name', 'Owner_Email',
					 'line_item_product_code']

	df = df.groupby(index).sum().reset_index()

	fieldnames = ['Year', 'Month', 'Account ID', 'Account Name', 'Licesne Plate', 'Environment', 'Billing Group', 'Owner Name', 'Owner Email',
				  'AWS Service']

	wb = Workbook()
	ws = wb.active

	for r in dataframe_to_rows(df, index=True, header=True):
		ws.append(r)

	wb.save(f"{summary_output_file}.xlsx")
