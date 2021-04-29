import csv

import numpy as np
import pandas as pd
from jinja2 import Environment, FileSystemLoader

from openpyxl import Workbook
from openpyxl.utils.dataframe import dataframe_to_rows


def read_file_into_dataframe(local_file):
	conver_dict = {'line_item_usage_account_id': str}
	pd.set_option('display.float_format', '${:.2f}'.format)
	df = pd.read_csv(local_file, dtype=conver_dict)

	return df


def enhance_with_metadata(df, team_index_by_account_id):
	# Account ID	Service Name	CITZ Internal Project Code	Owner Name	Account Name	Account Owner Email	Account Status
	# df['Team'] = df['line_item_usage_account_id'].apply(lambda x: team_index_by_account_id.get(x, "Core"))
	core_team = {
		"business_unit": "SEA Core",
		"contact_email": "julian.subda@gov.bc.ca",
		"contact_name": "Julian Subda",
		"name": "NA"
	}
	df['Team'] = df['line_item_usage_account_id'].apply(
		lambda x: team_index_by_account_id.get(x, core_team)['business_unit'])
	df['Owner_Name'] = df['line_item_usage_account_id'].apply(
		lambda x: team_index_by_account_id.get(x, core_team)['contact_name'])
	df['Owner_Email'] = df['line_item_usage_account_id'].apply(
		lambda x: team_index_by_account_id.get(x, core_team)['contact_email'])
	df['Account_Name'] = df['line_item_usage_account_id'].apply(
		lambda x: team_index_by_account_id.get(x, core_team)['name'])


def make_team_lookup(teams):
	team_index_by_account_id = {}
	team_details_by_account_id = {}

	for team in teams:
		for details in team['account_details']:
			team_details_by_account_id[details['id']] = details

	for team in teams:
		for account_id in team['accountIds']:
			team_details = team_details_by_account_id[account_id]
			team.update(team_details)
			team_index_by_account_id[account_id] = team

	return team_index_by_account_id


def report(query_results_file, report_output_path, query_parameters):
	month = query_parameters['month']
	year = query_parameters['year']

	team_index_by_account_id = make_team_lookup(query_parameters['teams'])
	df = read_file_into_dataframe(query_results_file)
	enhance_with_metadata(df, team_index_by_account_id)

	for team in query_parameters['teams']:
		accountIds = team['accountIds']
		bu = team['business_unit']

		index = ['year', 'month', 'line_item_usage_account_id', 'Account_Name', 'Team', 'Owner_Name', 'Owner_Email',
				 'line_item_product_code']

		billing_temp = df.query(
			f'year == [{year}] and month == [{month}] and (line_item_usage_account_id in {accountIds})')
		billing = pd.pivot_table(billing_temp,
								 index=index,
								 values=['line_item_blended_cost'], aggfunc=[np.sum], fill_value=0, margins=True,
								 margins_name='Total')

		env = Environment(loader=FileSystemLoader('.'))
		template = env.get_template("report.html")

		template_vars = {
			"title": "AWS Report",
			"pivot_table": billing.to_html(),
			"business_unit": bu
		}

		html_out = template.render(template_vars)

		report_name = f"{year}-{month}-{bu}.html"
		report_file_name = f"{report_output_path}/{report_name}"

		with open(report_file_name, "w") as text_file:
			text_file.write(html_out)


def aggregate(query_results_file, query_parameters, summary_output_file):
	team_index_by_account_id = make_team_lookup(query_parameters['teams'])
	df = read_file_into_dataframe(query_results_file)
	enhance_with_metadata(df, team_index_by_account_id)

	df = df.groupby(
		['year', 'month', 'line_item_usage_account_id', 'Account_Name', 'Team', 'Owner_Name', 'Owner_Email',
		 'line_item_product_code']).sum().reset_index()

	fieldnames = ['Year', 'Month', 'Account ID', 'Account Name', 'Billing Group', 'Owner Name', 'Owner Email',
				  'AWS Service']

	wb = Workbook()
	ws = wb.active

	for r in dataframe_to_rows(df, index=True, header=True):
		ws.append(r)

	wb.save(f"{summary_output_file}.xlsx")

# with open(summary_output_file, 'w', newline='') as csvfile:
# 	line_item_writer = csv.writer(csvfile, delimiter=',', quotechar='"', quoting=csv.QUOTE_ALL)
# 	line_item_writer.writerow(fieldnames)
#
# 	for index, row in df.iterrows():
# 		line_item_writer.writerow([row['year'], row['month'], row['line_item_usage_account_id'], row['Account_Name'], row['Team'], row['Owner_Name'], row['Owner_Email'],
# 								   row['line_item_product_code'], "{:10.4f}".format(row['line_item_blended_cost'])])
