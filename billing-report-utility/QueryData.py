import logging
import os
import sys
from datetime import datetime

import boto3
from botocore.exceptions import ClientError
from retrying import retry

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
logger.addHandler(handler)


class QueryData:

	def __init__(self, query_parameters):
		self.query_parameters = query_parameters
		self.aws_default_region = os.environ['AWS_DEFAULT_REGION']
		self.athena_query_role_to_assume = os.environ.get("ATHENA_QUERY_ROLE_TO_ASSUME_ARN")
		self.athena_query_output_bucket_name = os.environ.get("ATHENA_QUERY_OUTPUT_BUCKET_ARN")
		self.athena_query_database = os.environ.get("ATHENA_QUERY_DATABASE")

		self.s3_output = "s3://" + self.athena_query_output_bucket_name

	def __get_sts_credentials(self):
		# Assume cross account role needed to perform Athena Queries
		logger.info("Starting STS Client Connection")
		sts_client = boto3.client(
			'sts',
			region_name=self.aws_default_region,
			endpoint_url="https://sts.ca-central-1.amazonaws.com"
		)
		logger.info("STS Client Connection Complete")

		try:
			assumed_role_object = sts_client.assume_role(
				DurationSeconds=3600,
				RoleArn=self.athena_query_role_to_assume,
				RoleSessionName="AthenaCost"
			)
		except ClientError as err:
			if err.response["Error"]:
				logger.info("STS Assume Role Error: ", err)
				logger.error("STS Assume Role Error: ", err)
			return err

		# From the response that contains the assumed role, get the temporary
		# credentials that can be used to make subsequent API calls
		return assumed_role_object['Credentials']

	@retry(stop_max_attempt_number=10, wait_exponential_multiplier=300, wait_exponential_max=1 * 60 * 1000)
	def __poll_status(self, _id):
		credentials = self.__get_sts_credentials()

		# Use the temporary credentials that AssumeRole returns to make a connection
		# to Amazon Athena
		try:
			athena = boto3.client(
				'athena',
				aws_access_key_id=credentials['AccessKeyId'],
				aws_secret_access_key=credentials['SecretAccessKey'],
				aws_session_token=credentials['SessionToken'],
			)
		except ClientError as err:
			logger.error("S3 Client Connection Error: ", err)
			return err

		result = athena.get_query_execution(QueryExecutionId=_id)
		state = result['QueryExecution']['Status']['State']

		logging.debug(f"execution_id={_id}, state={state}, time={datetime.now().time()}")

		if state == 'SUCCEEDED' or state == 'FAILED':
			return
		else:
			raise Exception

	def __run_query(self, query):
		credentials = self.__get_sts_credentials()

		# Use the temporary credentials that AssumeRole returns to make a connection
		# to Amazon Athena
		try:
			athena = boto3.client(
				'athena',
				aws_access_key_id=credentials['AccessKeyId'],
				aws_secret_access_key=credentials['SecretAccessKey'],
				aws_session_token=credentials['SessionToken'],
			)
		except ClientError as err:
			logger.error("S3 Client Connection Error: ", err)
			return err

		response = athena.start_query_execution(
			QueryString=query,
			QueryExecutionContext={
				'Database': self.athena_query_database
			},
			ResultConfiguration={
				'OutputLocation': self.s3_output,
			})

		query_execution_id = response['QueryExecutionId']

		# block until the query execution completes
		self.__poll_status(query_execution_id)

		# check the result
		result = athena.get_query_execution(QueryExecutionId=query_execution_id)['QueryExecution']['Status']['State']

		if result == 'SUCCEEDED':
			logging.info(f"Query SUCCEEDED: {query_execution_id}")

			return query_execution_id
		else:
			raise Exception

	def query_usage_charges(self):
		format_string = "%Y-%m-%dT%H:%M:%S"
		start_date_string = datetime.strftime(self.query_parameters['start_date'], format_string)
		end_date_string = datetime.strftime(self.query_parameters['end_date'], format_string)

		# SQL Query to execute
		query = (f"""
		   SELECT
			line_item_usage_account_id, line_item_product_code, product_product_name, line_item_blended_cost, year, month
			FROM cost_and_usage_report
			WHERE line_item_usage_start_date > CAST(From_iso8601_timestamp('{start_date_string}') AS timestamp)
			AND line_item_usage_end_date <= CAST(From_iso8601_timestamp('{end_date_string}') AS timestamp)
		""")

		if 'account_ids' in self.query_parameters:
			account_ids = ", ".join(f"'{id}'" for id in self.query_parameters.get('account_ids'))
			account_id_where_clause = f" AND line_item_usage_account_id in ( {account_ids} )"
			query += account_id_where_clause

		logging.debug(query)

		return self.__run_query(query)
