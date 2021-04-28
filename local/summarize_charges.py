import csv

import numpy as np
import pandas as pd
from jinja2 import Environment, FileSystemLoader


def read_file_into_dataframe(local_file):
	conver_dict = {'line_item_usage_account_id': str}
	pd.set_option('display.float_format', '${:.2f}'.format)
	df = pd.read_csv(local_file, dtype=conver_dict)

	return df


def enhance_with_metadata(df, team_index_by_account_id):
	# Account ID	Service Name	CITZ Internal Project Code	Owner Name	Account Name	Account Owner Email	Account Status
	df['Team'] = df['line_item_usage_account_id'].apply(lambda x: team_index_by_account_id.get(x, "Core"))
	# df['Team'] = df['line_item_usage_account_id'].apply(lambda x: team_index_by_account_id.get(x['business_unit'], "Core"))



def make_team_lookup(teams):
	team_index_by_account_id = {}

	for team in teams:
		for account_id in team['accountIds']:
			team_index_by_account_id[account_id] = team['business_unit']

	return team_index_by_account_id

# def make_team_lookup(teams):
# 	team_index_by_account_id = {}
#
# 	for team in teams:
# 		for account_id in team['accountIds']:
# 			team_index_by_account_id[account_id] = team
#
# 	return team_index_by_account_id


def report(query_results_file, report_output_path, query_parameters):
	month = query_parameters['month']
	year = query_parameters['year']

	team_index_by_account_id = make_team_lookup(query_parameters['teams'])
	df = read_file_into_dataframe(query_results_file)
	enhance_with_metadata(df, team_index_by_account_id)

	for team in query_parameters['teams']:
		accountIds = team['accountIds']
		bu = team['business_unit']

		billing_temp = df.query(
			f'year == [{year}] and month == [{month}] and (line_item_usage_account_id in {accountIds})')
		billing = pd.pivot_table(billing_temp,
								 index=['year', 'month', 'line_item_usage_account_id', 'Team', 'line_item_product_code'],
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
		['year', 'month', 'line_item_usage_account_id', 'Team', 'line_item_product_code']).sum().reset_index()

	with open(summary_output_file, 'w', newline='') as csvfile:
		line_item_writer = csv.writer(csvfile, delimiter=',', quotechar='"', quoting=csv.QUOTE_MINIMAL)

		for index, row in df.iterrows():
			line_item_writer.writerow([row['year'], row['month'], row['line_item_usage_account_id'], row['Team'],
									   row['line_item_product_code'], "{:10.4f}".format(row['line_item_blended_cost'])])
