import logging
import os
import sys

import boto3
from botocore.exceptions import ClientError

from collections import defaultdict
from pathlib import Path
from jinja2 import Environment, FileSystemLoader

import summarize_charges
from QueryData import QueryData
from helpers import query_org_accounts, get_sts_credentials, send_email

jinja_env = Environment(loader=FileSystemLoader('.'))
jinja_template = jinja_env.get_template("./templates/email_body.jinja2")

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
logger.addHandler(handler)


class BillingManager:

	def __init__(self, query_parameters):
		self.query_parameters = query_parameters
		self.sts_endpoint = "https://sts.ca-central-1.amazonaws.com"
		self.athena_query_role_to_assume = os.environ["ATHENA_QUERY_ROLE_TO_ASSUME_ARN"]
		self.athena_query_output_bucket = os.environ["ATHENA_QUERY_OUTPUT_BUCKET"]
		self.athena_query_output_bucket_name = os.environ["ATHENA_QUERY_OUTPUT_BUCKET"]
		self.athena_query_database = os.environ["ATHENA_QUERY_DATABASE"]
		self.container_creds_uri = os.environ.get("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")

		self.quarterly_report_config = None

		if os.environ['AWS_DEFAULT_REGION']:
			self.aws_default_region = os.environ['AWS_DEFAULT_REGION']
		else:
			self.aws_default_region = "ca-central-1"

		self.s3_output = "s3://" + self.athena_query_output_bucket_name
		self.role_session_name = "AthenaQuery"
		self.delivery_outbox = defaultdict(set)

		# make sure the local output directory exists, creating if necessary
		current_dir = os.path.dirname(os.path.realpath(__file__))
		self.output_dir = f"{current_dir}/output"
		Path(self.output_dir).mkdir(parents=True, exist_ok=True)

		self.query_results_dir_name = "query_results"
		self.summarized_dir_name = "summarized"
		self.reports_dir_name = "reports"

		self.org_accounts = query_org_accounts()

		# create a lookup to allow us to easily derive the "owner" email address for a given billing group
		self.emails_for_billing_groups = defaultdict(set)
		for account in self.org_accounts:
			self.emails_for_billing_groups[account['billing_group']].add(account['admin_contact_email'])

	def create_project_set_lookup(self):
		project_set_lookup = {}
		for account in self.org_accounts:
			# TODO: sorting by license_plate doesn't handle core accounts
			if account["license_plate"] in project_set_lookup:
				project_set_lookup[account["license_plate"]].append(account)
			else:
				project_set_lookup[account["license_plate"]] = [account]
		return project_set_lookup

	@staticmethod
	def format_project_set_info(project_set):
		formatted_project_set = project_set[0]["Project"] + "\n"
		for account in project_set:
			# NOTE: "name" is the same as "license_plate"-"Environment"
			formatted_project_set += "  - " + account["id"] + " - " + account["name"] + "\n"
		return formatted_project_set

	def format_account_info_for_email(self, billing_group):
		formatted_account_info = ""
		project_set_lookup = self.create_project_set_lookup()
		for project_set in project_set_lookup:
			if project_set_lookup[project_set][0]["billing_group"] == billing_group:
				formatted_account_info += "\n" + self.format_project_set_info(project_set_lookup[project_set])
		return formatted_account_info

	def __deliver_reports(self, billing_group_totals):

		for billing_group, attachments in self.delivery_outbox.items():
			billing_group_email = self.emails_for_billing_groups.get(billing_group).pop()
			recipient_email = billing_group_email

			subject = (
				f"Cloud Consumption Report ${billing_group_totals.get(billing_group)} for "
				f"{self.query_parameters['start_date'].strftime('%d-%m-%Y')} to "
				f"{self.query_parameters['end_date'].strftime('%d-%m-%Y')}."
			)

			body_text = jinja_template.render({
				"billing_group_email": billing_group_email,
				"start_date": self.query_parameters.get("start_date"),
				"end_date": self.query_parameters.get("end_date"),
				"billing_group_total": billing_group_totals.get(billing_group),
				"list_of_accounts": self.format_account_info_for_email(billing_group)
			})

			logger.debug(f"Sending email to '{recipient_email}' with subject '{subject}'")

			if "carbon_copy" in self.query_parameters:
				logger.debug(f"Email carbon copy will be sent to '{self.query_parameters['carbon_copy']}'.")

			email_result = send_email(
				sender="info@cloud.gov.bc.ca", recipient=recipient_email,
				subject=subject, cc=self.query_parameters.get('carbon_copy'),
				body_text=body_text, attachments=attachments
			)

			logger.debug(f"Email result: {email_result}.")

	def __run_query(self):
		logger.info("Querying data...")

		# if we are querying for specific billing group(s), we need to pass in account_ids
		if self.query_parameters.get('billing_groups'):
			account_ids = set(map(lambda a: a['id'], self.org_accounts))
			self.query_parameters['account_ids'] = account_ids

			logger.debug(f"Querying for account_ids '{account_ids}'")

		query_data = QueryData(self.query_parameters)
		return query_data.query_usage_charges()

	def __download_query_results(self, query_execution_id, output_file_local_path):
		credentials = get_sts_credentials(
			self.athena_query_role_to_assume, self.aws_default_region,
			self.sts_endpoint, self.role_session_name
		)

		# Use the temporary credentials that AssumeRole returns to make a connection
		# to S3 in Operations account
		try:
			s3_resource = boto3.resource(
				's3',
				aws_access_key_id=credentials['AccessKeyId'],
				aws_secret_access_key=credentials['SecretAccessKey'],
				aws_session_token=credentials['SessionToken'],
			)
		except ClientError as err:
			logger.error(f"A boto3 client error has occurred: {err}")
			return err

		logger.info("Downloading query results...")

		output_file_name = f"cur/{query_execution_id}.csv"
		s3_output_file = s3_resource.Object(self.athena_query_output_bucket_name, output_file_name)
		s3_output_file.download_file(f"{output_file_local_path}")
		# s3_output_file.delete()

		# metadata_file = f"cur/{query_execution_id}.metadata"
		# s3_output_metadata_file = s3_resource.Object(self.athena_query_output_bucket_name, metadata_file)
		# s3_output_metadata_file.delete()

		logger.info(f"Downloaded output file to '{output_file_local_path}'")

	def queue_attachment(self, billing_group, attachment):
		# we will queue up the attachments generated in the processing step and deliver to recipients after processing
		self.delivery_outbox[billing_group].add(attachment)

	def summarize(self, query_results_output_file_local_path, summary_output_path):
		logger.info("Summarizing query results...")

		summarize_charges.aggregate(
			query_results_output_file_local_path, summary_output_path,
			self.org_accounts, self.query_parameters, self.queue_attachment
		)

		logger.info(f"Summarized data stored at '{summary_output_path}'")

	def reports(self, query_results_output_file_local_path, report_output_dir):
		logger.info("Generating reports...")

		billing_group_totals = summarize_charges.report(
			query_results_output_file_local_path, report_output_dir, self.org_accounts,
			self.query_parameters, self.queue_attachment, self.quarterly_report_config
		)

		return billing_group_totals

	def do(self, existing_file=None):

		query_results_output_file_local_path = existing_file

		if not query_results_output_file_local_path:
			query_execution_id = self.__run_query()
			logger.debug(f"query_execution_id = '{query_execution_id}'")

			output_file_name = "query_results.csv"
			output_local_path = f"{self.output_dir}/{query_execution_id}/{self.query_results_dir_name}"
			Path(output_local_path).mkdir(parents=True, exist_ok=True)
			query_results_output_file_local_path = f"{output_local_path}/{output_file_name}"

			self.__download_query_results(query_execution_id, query_results_output_file_local_path)

		else:
			logger.info(f"Skipping query. Processing local file '{query_results_output_file_local_path}'")

		logger.debug(f"query_results_output_file_local_path = '{query_results_output_file_local_path}'")

		base_output_path = "/".join(query_results_output_file_local_path.split("/")[:-2])

		summary_local_path = f"{base_output_path}/{self.summarized_dir_name}"
		Path(summary_local_path).mkdir(parents=True, exist_ok=True)
		self.summarize(query_results_output_file_local_path, summary_local_path)

		reports_local_path = f"{base_output_path}/{self.reports_dir_name}"
		Path(reports_local_path).mkdir(parents=True, exist_ok=True)
		billing_group_totals = self.reports(query_results_output_file_local_path, reports_local_path)

		self.__deliver_reports(billing_group_totals)


