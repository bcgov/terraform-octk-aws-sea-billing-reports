import json
import logging
import os

import boto3
from progress.bar import Bar

import query_data
import summarize_charges

from pathlib import Path

from fabulous import text

logger = logging.getLogger(__name__)


class BillingManager:

	@staticmethod
	def display_step(message):
		print(message)

	@staticmethod
	def read_input_file(teams_file):
		data = None
		with open(teams_file) as f:
			data = json.load(f)

		return data

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

		return output_file_local_path

	def summarize(self, query_results_output_file_local_path):
		self.display_step("Summarizing query results...")
		summary_file_name = query_results_output_file_local_path.split('/')[::-1][0]
		summary_file_full_path = f"{self.summary_output_dir}/charges-{summary_file_name}"
		summarize_charges.aggregate(query_results_output_file_local_path, self.query_parameters, summary_file_full_path)
		logger.debug(f"Summarize data output file is '{summary_file_full_path}")

	def reports(self, query_results_output_file_local_path):
		self.display_step("Generating reports...")
		summarize_charges.report(query_results_output_file_local_path, self.report_output_dir, self.query_parameters)

	def do(self):
		output_file_name = self.run_query()
		logger.debug(f"output_file_name is '{output_file_name}'")

		query_results_output_file_local_path = self.download_query_results(output_file_name)
		logger.debug(f"query_results_output_file_local_path is '{query_results_output_file_local_path}'")

		self.summarize(query_results_output_file_local_path)
		self.reports(query_results_output_file_local_path)

	def __init__(self, input_file='teams.json'):
		# The database to which the query belongs
		self.database = os.environ.get("ATHENA_DATABASE", "athenacurcfn_cost_and_usage_report")

		# S3 output Bucket name - where the results of the athena query is stored as a csv file
		self.s3_bucket = os.environ.get("S3_BUCKET", "billing-reports-334132478648")
		self.s3_output = 's3://' + self.s3_bucket  # S3 Bucket to store results

		self.s3 = boto3.resource('s3')

		self.display_step("Reading query parameters.")
		self.query_parameters = self.read_input_file(input_file)

		current_dir = os.path.dirname(os.path.realpath(__file__))
		output_dir = f"{current_dir}/output"

		self.query_output_dir = f"{output_dir}/query_output"
		Path(self.query_output_dir).mkdir(parents=True, exist_ok=True)

		self.summary_output_dir = f"{output_dir}/summarized"
		Path(self.summary_output_dir).mkdir(parents=True, exist_ok=True)

		self.report_output_dir = f"{output_dir}/reports"
		Path(self.report_output_dir).mkdir(parents=True, exist_ok=True)


def main():
	print("Billing!")
	bill_manager = BillingManager()
	bill_manager.do()


if __name__ == "__main__":
	logger.setLevel(logging.DEBUG)
	main()
