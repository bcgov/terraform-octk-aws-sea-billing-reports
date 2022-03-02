import argparse
import calendar
import json
import logging
import os
import re
from collections import defaultdict
from datetime import date, datetime, timezone, timedelta

import boto3
from botocore.exceptions import ClientError
from jinja2 import Environment, FileSystemLoader

import query_data
import summarize_charges

from pathlib import Path

from email_delivery import EmailDelivery

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

	@staticmethod
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

		def get_account_name_element(account_deets, element_index):
			account_email = account_deets['email']
			account_name = account_deets['name']

			if re.search("app", account_email):
				return account_name.split("-")[element_index]
			else:
				return account_name

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

	def format_account_info(self):
		formatted_account_info = ""
		for account in self.org_accounts:
			formatted_account_info = formatted_account_info + "\n" + account["license_plate"] + "-" + account["Environment"] + " - " + account["name"]
		return formatted_account_info

	def deliver_reports(self):
		if self.delivery_config:

			for billing_group, attachments in self.delivery_outbox.items():
				billing_group_email = self.emails_for_billing_groups.get(billing_group).pop()
				recipient_email = self.delivery_config.get("recipient_override") or billing_group_email
				# TODO: add total cost here
				subject = self.delivery_config.get("subject") or f"Cloud Pathfinder Cloud Service Consumption Report for {self.query_parameters['start_date'].strftime('%d-%m-%Y')} to {self.query_parameters['end_date'].strftime('%d-%m-%Y')}."

				# TODO: add list of project sets here -> use "org_accounts" -> need a reduced list based on billing groups
				# todo implement HTML email body
				body_text = self.template.render({
					"start_date" : self.query_parameters.get("start_date"),
					"end_date" : self.query_parameters.get("end_date"),
					"billing_group_email" : billing_group_email,
					"list_of_accounts": self.format_account_info()
				})

				logger.debug(f"Sending email to '{recipient_email}' with subject '{subject}'")

				if "carbon_copy" in self.query_parameters:
					logger.debug(f"Email carbon copy will be sent to '{self.query_parameters['carbon_copy']}'.")

				email_result = self.emailer.send_email(sender="info@cloud.gov.bc.ca",
													   recipient=recipient_email,
													   subject=subject,
													   cc=self.query_parameters.get('carbon_copy'),
													   body_text=body_text,
													   attachments=attachments)

				logger.debug(f"Email result: {email_result}.")
		else:
			logger.debug("Skipping email delivery.")

	def run_query(self):
		self.display_step("Querying data...")

		# if we are querying for specific billing group(s), we need to pass in account_ids
		if self.query_parameters.get('billing_groups'):
			account_ids = set(map(lambda a: a['id'], self.org_accounts))
			self.query_parameters['account_ids'] = account_ids

			logger.debug(f"Querying for account_ids '{account_ids}'")

		return query_data.query_usage_charges(self.query_parameters, self.database, self.s3_output)

	def download_query_results(self, query_execution_id, output_file_local_path):
		self.display_step("Downloading query results...")

		output_file_name = f"{query_execution_id}.csv"
		s3_output_file = self.s3.Object(self.s3_bucket, output_file_name)
		s3_output_file.download_file(f"{output_file_local_path}")
		s3_output_file.delete()

		metadata_file = f"{query_execution_id}.metadata"
		s3_output_metadata_file = self.s3.Object(self.s3_bucket, metadata_file)
		s3_output_metadata_file.delete()

		self.display_step(f"Downloaded output file to '{output_file_local_path}'")

	def queue_attachment(self, billing_group, attachment):
		# we will queue up the attachments generated in the processing step and deliver to recipients after processing
		self.delivery_outbox[billing_group].add(attachment)

	def summarize(self, query_results_output_file_local_path, summary_output_path):
		self.display_step("Summarizing query results...")

		summarize_charges.aggregate(query_results_output_file_local_path, summary_output_path, self.org_accounts,
									self.query_parameters, self.queue_attachment)

		self.display_step(f"Summarized data stored at '{summary_output_path}'")

	def reports(self, query_results_output_file_local_path, report_output_dir):
		self.display_step("Generating reports...")

		summarize_charges.report(query_results_output_file_local_path, report_output_dir, self.org_accounts,
								 self.query_parameters, self.queue_attachment)

	def do(self, existing_file=None):

		query_results_output_file_local_path = existing_file

		if not query_results_output_file_local_path:
			query_execution_id = self.run_query()
			logger.debug(f"query_execution_id = '{query_execution_id}'")

			output_file_name = "query_results.csv"
			output_local_path = f"{self.output_dir}/{query_execution_id}/{self.query_results_dir_name}"
			Path(output_local_path).mkdir(parents=True, exist_ok=True)
			query_results_output_file_local_path = f"{output_local_path}/{output_file_name}"

			self.download_query_results(query_execution_id, query_results_output_file_local_path)

		else:
			self.display_step(f"Skipping query.  Processing local file '{query_results_output_file_local_path}'")

		logger.debug(f"query_results_output_file_local_path = '{query_results_output_file_local_path}'")

		base_output_path = "/".join(query_results_output_file_local_path.split("/")[:-2])

		summary_local_path = f"{base_output_path}/{self.summarized_dir_name}"
		Path(summary_local_path).mkdir(parents=True, exist_ok=True)
		self.summarize(query_results_output_file_local_path, summary_local_path)

		reports_local_path = f"{base_output_path}/{self.reports_dir_name}"
		Path(reports_local_path).mkdir(parents=True, exist_ok=True)
		self.reports(query_results_output_file_local_path, reports_local_path)

		self.deliver_reports()

	def __init__(self, query_parameters, athena_database="athenacurcfn_cost_and_usage_report",
				 query_output_bucket="bcgov-aws-sea-billing-reports", delivery_config=None):
		# The database to which the query belongs
		self.database = athena_database

		self.init_s3(query_output_bucket)

		self.display_step("Discovering accounts in organization...")
		self.org_accounts = self.query_org_accounts()

		# filter the accounts based on provided billing_groups parameter, if specified
		if query_parameters.get("billing_groups"):
			bgs = query_parameters.get("billing_groups").split(",")
			logger.debug(f"Processing billing details for Billing Groups '{bgs}'.")
			self.org_accounts = [a for a in self.org_accounts if a['billing_group'] in bgs]
			logger.debug(f"{len(self.org_accounts)} accounts in target billing groups...")
			logger.debug(f"target billing groups: '{self.org_accounts}'")

		self.delivery_config = delivery_config
		self.delivery_outbox = defaultdict(set)

		env = Environment(loader=FileSystemLoader('.'))
		self.template = env.get_template("./templates/email_body.jinja2")

		# TODO: create something similar for names, and project names or whatever thats called
		# create a lookup to allow us to easily derive the "owner" email address for a given billing group
		self.emails_for_billing_groups = defaultdict(set)
		for account in self.org_accounts:
			self.emails_for_billing_groups[account['billing_group']].add(account['admin_contact_email'])

		self.emailer = EmailDelivery()

		self.query_parameters = query_parameters

		# make sure the local output directory exists, creating if necessary
		current_dir = os.path.dirname(os.path.realpath(__file__))
		self.output_dir = f"{current_dir}/output"
		Path(self.output_dir).mkdir(parents=True, exist_ok=True)

		self.query_results_dir_name = "query_results"
		self.summarized_dir_name = "summarized"
		self.reports_dir_name = "reports"

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
	print("Cloud Pathfinder Billing Utility!")

	deliver = params.get('deliver', False)

	delivery_config = None
	if deliver:
		delivery_config = {
			"deliver": deliver,
			"recipient_override": params.get("recipient_override")
		}

	bill_manager = BillingManager(params, delivery_config=delivery_config)

	bill_manager.do(existing_file=params['query_results_local_file'])


if __name__ == "__main__":

	def handle_date_range(args):
		args['start_date'] = datetime.combine(args['start'], datetime.min.time(), tzinfo=timezone.utc)
		# small fiddle below required to get *actual midnight* at end of date range period - we add a day, but set to earliest time
		args['end_date'] = datetime.combine(args['end'] + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)

		return args


	def handle_billing_period(args):
		billing_period = args['billing_period']

		# set to first day of month
		billing_period_start = billing_period.replace(day=1)
		# set to start of day
		billing_period_start = datetime.combine(billing_period_start, datetime.min.time(), tzinfo=timezone.utc)

		# set to *first* day of next month
		billing_period_end = billing_period.replace(
			day=calendar.monthrange(billing_period.year, billing_period.month)[1]) + timedelta(days=1)
		# set to start of day
		billing_period_end = datetime.combine(billing_period_end, datetime.min.time(), tzinfo=timezone.utc)

		args['start_date'] = billing_period_start
		args['end_date'] = billing_period_end

		return args

	def handle_weekly(args):
		billing_period_end = date.today() - timedelta(days=1)
		billing_period_end = datetime.combine(billing_period_end, datetime.max.time(), tzinfo=timezone.utc)

		billing_period_start = billing_period_end - timedelta(days=6)
		billing_period_start = datetime.combine(billing_period_start, datetime.min.time(), tzinfo=timezone.utc)

		args['start_date'] = billing_period_start
		args['end_date'] = billing_period_end

		return args

	def configure_logging(level_string):
		levels = {
			'critical': logging.CRITICAL,
			'error': logging.ERROR,
			'warn': logging.WARNING,
			'warning': logging.WARNING,
			'info': logging.INFO,
			'debug': logging.DEBUG
		}

		logging.basicConfig()
		logger.setLevel(levels.get(level_string.lower()))


	parser = argparse.ArgumentParser(prog='billing', description='Processing billing data.')

	subparsers = parser.add_subparsers()

	date_range_subparser = subparsers.add_parser('date', aliases=['dt'])
	date_range_subparser.add_argument('-s', '--start', type=date.fromisoformat)
	date_range_subparser.add_argument('-e', '--end', type=date.fromisoformat)
	date_range_subparser.set_defaults(func=handle_date_range)

	weekly_subparser = subparsers.add_parser('weekly', aliases=['w'])
	weekly_subparser.set_defaults(func=handle_weekly)

	billing_period_subparser = subparsers.add_parser('billperiod', aliases=['bp'])
	billing_period_subparser.add_argument('-b', '--billing_period', type=date.fromisoformat)
	billing_period_subparser.set_defaults(func=handle_billing_period)

	parser.add_argument('-d', '--deliver', type=bool, default=False, help='True/False value inidicating whether email delivery should be done.')
	parser.add_argument('-ro', '--recipient_override', type=str, help='Email address (typically for testing/verification) to which reports will be delivered instead of account admins.')
	parser.add_argument('-cc', '--carbon_copy', type=str, help='Email address to which reports will be delivered to, in addition to other recipients.')
	parser.add_argument('-bgs', '--billing_groups', type=str, help='Comma-separated list of billing groups for which to process billing data.')
	parser.add_argument('-ll', '--log_level', type=str,
						 default='warning',
						 help='Specify logging level. Example --loglevel debug' )

	# argument to allow use of existing query results file
	parser.add_argument('-q', '--query_results_local_file', type=str,
						help='Full path to an existing, query output file in CSV format on the local system. If not specified, an Athena query will be performed, and the query results file will be downloaded to the local system.')


	args = parser.parse_args()
	command_line_args = vars(args)
	args.func(command_line_args)

	configure_logging(args.log_level)

	logger.debug(f"Start date: {command_line_args['start_date']}")
	logger.debug(f"End  date: {command_line_args['end_date']}")

	main(command_line_args)
