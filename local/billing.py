import argparse
import json
import logging
import os
from datetime import datetime

import boto3
from botocore.exceptions import ClientError

import query_data
import summarize_charges

from pathlib import Path

logger = logging.getLogger(__name__)


class BillingManager:

	@staticmethod
	def display_step(message):
		print(message)

	@staticmethod
	def read_input_file(teams_file):
		with open(teams_file) as f:
			data = json.load(f)

		return data

	def query_org_accounts(self):
		org_client = boto3.client('organizations')

		# we have lots of accounts - use a Paginator
		paginator = org_client.get_paginator('list_accounts')

		page_iterator = paginator.paginate()

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
				accounts.append(account_details)

		return accounts

	def run_query(self):
		self.display_step("Querying data...")
		return query_data.query(self.query_parameters, self.database, self.s3_output)

	def download_query_results(self, output_file_name):
		self.display_step("Downloading query results...")
		s3_output_file = self.s3.Object(self.s3_bucket, output_file_name)
		output_file_local_path = f"{self.query_output_dir}/{output_file_name}"
		s3_output_file.download_file(output_file_local_path)
		s3_output_file.delete()
		s3_output_metadata_file = self.s3.Object(self.s3_bucket, "{output_file_name}.metadata")
		s3_output_metadata_file.delete()

		self.display_step(f"Downloaded output file to '{output_file_local_path}'")

		return output_file_local_path

	def summarize(self, query_results_output_file_local_path):
		self.display_step("Summarizing query results...")
		summary_file_name = query_results_output_file_local_path.split('/')[::-1][0]
		summary_file_full_path = f"{self.summary_output_dir}/charges-{summary_file_name}".replace("csv", "xlsx")
		summarize_charges.aggregate(query_results_output_file_local_path, self.org_accounts, summary_file_full_path)

		logger.debug(f"Summarize data output file is '{summary_file_full_path}")
		self.display_step(f"Summarized data stored at '{summary_file_full_path}'")

	def reports(self, query_results_output_file_local_path):
		self.display_step("Generating reports...")
		summarize_charges.report(query_results_output_file_local_path, self.report_output_dir, self.org_accounts,
								 self.query_parameters)

	def do(self, existing_file=None):

		query_results_output_file_local_path = existing_file

		if not query_results_output_file_local_path:
			output_file_name = self.run_query()
			logger.debug(f"output_file_name = '{output_file_name}'")

			query_results_output_file_local_path = self.download_query_results(output_file_name)
		else:
			self.display_step(f"Skipping query.  Processing local file '{query_results_output_file_local_path}'")

		logger.debug(f"query_results_output_file_local_path = '{query_results_output_file_local_path}'")

		self.summarize(query_results_output_file_local_path)
		self.reports(query_results_output_file_local_path)

	def __init__(self, query_parameters, athena_database="athenacurcfn_cost_and_usage_report", query_output_bucket="bcgov-aws-sea-billing-reports" ):
		# The database to which the query belongs
		self.database = athena_database

		self.init_s3(query_output_bucket)

		self.display_step("Discovering accounts in organization...")
		self.org_accounts = self.query_org_accounts()

		self.query_parameters = query_parameters

		current_dir = os.path.dirname(os.path.realpath(__file__))
		output_dir = f"{current_dir}/output"

		self.query_output_dir = f"{output_dir}/query_output"
		Path(self.query_output_dir).mkdir(parents=True, exist_ok=True)

		self.summary_output_dir = f"{output_dir}/summarized"
		Path(self.summary_output_dir).mkdir(parents=True, exist_ok=True)

		self.report_output_dir = f"{output_dir}/reports"
		Path(self.report_output_dir).mkdir(parents=True, exist_ok=True)

	def init_s3(self, query_output_bucket):
		# S3 output Bucket name - where the results of the athena query is stored as a csv file
		self.s3_bucket = query_output_bucket

		# S3 Bucket to store results
		self.s3_output = 's3://' + self.s3_bucket

		self.s3 = boto3.resource('s3')

		s3client = boto3.client("s3")

		try:
			s3client.head_bucket(Bucket=query_output_bucket)
		except ClientError:
			# bucket doesn't exist (or we have no access). try to create it below
			s3client.create_bucket(Bucket=query_output_bucket,
								   CreateBucketConfiguration={'LocationConstraint': s3client.meta.region_name})

def main(params):
	print("Billing!")

	query_parameters = {
		"year": params.year,
		"month": params.month
	}

	bill_manager = BillingManager(query_parameters)

	bill_manager.do(existing_file=params.query_results_local_file)


if __name__ == "__main__":
	logger.setLevel(logging.ERROR)
	parser = argparse.ArgumentParser(description='Processing billing data.')
	parser.add_argument('-y', '--year', type=int, default=datetime.today().year, help='The year for which we are interested in producing billing summary data and reports. If not specified, the current year is assumed.')
	parser.add_argument('-m', '--month', type=int, default=datetime.today().month, help='The month in the year (-y/--year) for which we are interested in producing billing suammary data and reports. If not specified, the current month is assumed.')
	parser.add_argument('-q', '--query_results_local_file', type=str, help='Full path to an existing, query output file in CSV format on the local system. If not specified, an Athena query will be performed, and the query results file will be downloaded to the local system.')
	main(parser.parse_args())
