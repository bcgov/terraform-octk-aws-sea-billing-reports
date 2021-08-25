import logging
from datetime import datetime

import boto3
from retrying import retry

# init client
athena = boto3.client('athena')


def query_usage_charges(query_parameters, database, s3_output):
	format_string = "%Y-%m-%dT%H:%M:%S"
	start_date_string = datetime.strftime(query_parameters['start_date'], format_string)
	end_date_string = datetime.strftime(query_parameters['end_date'], format_string)

	# SQL Query to execute
	query = (f"""
       SELECT
        line_item_usage_account_id, line_item_product_code, product_product_name, line_item_blended_cost, year, month
        FROM cost_and_usage_report
        WHERE line_item_usage_start_date > CAST(From_iso8601_timestamp('{start_date_string}') AS timestamp)
        AND line_item_usage_end_date <= CAST(From_iso8601_timestamp('{end_date_string}') AS timestamp)
    """)

	if 'account_ids' in query_parameters:
		account_ids = ", ".join(f"'{id}'" for id in query_parameters.get('account_ids'))
		account_id_where_clause = f" AND line_item_usage_account_id in ( {account_ids} )"
		query += account_id_where_clause

	logging.debug(query)

	return run_query(query, database, s3_output)


@retry(stop_max_attempt_number=10,
	   wait_exponential_multiplier=300,
	   wait_exponential_max=1 * 60 * 1000)
def poll_status(_id):
	result = athena.get_query_execution(QueryExecutionId=_id)
	state = result['QueryExecution']['Status']['State']

	logging.debug(f"execution_id={_id}, state={state}, time={datetime.now().time()}")

	if state == 'SUCCEEDED' or state == 'FAILED':
		return
	else:
		raise Exception


def run_query(query, database, s3_output):
	response = athena.start_query_execution(
		QueryString=query,
		QueryExecutionContext={
			'Database': database
		},
		ResultConfiguration={
			'OutputLocation': s3_output,
		})

	query_execution_id = response['QueryExecutionId']

	# block until the query execution completes
	poll_status(query_execution_id)

	# check the result
	result = athena.get_query_execution(QueryExecutionId=query_execution_id)['QueryExecution']['Status']['State']

	if result == 'SUCCEEDED':
		logging.info(f"Query SUCCEEDED: {query_execution_id}")

		return query_execution_id
	else:
		raise Exception
