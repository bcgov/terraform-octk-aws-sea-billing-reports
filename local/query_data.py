import logging

import boto3
from retrying import retry

# init clients
athena = boto3.client('athena')


def query(query_parameters, database, s3_output):
	# @todo add product_product_name column
	# SQL Query to execute
	query = (f"""
       SELECT
        line_item_usage_account_id, line_item_product_code, product_product_name, line_item_blended_cost, year, month
        FROM cost_and_usage_report
        WHERE year = '{query_parameters['year']}' and month = '{query_parameters['month']}'
        and line_item_blended_cost > 0
    """)

	return run_query(query, database, s3_output)


@retry(stop_max_attempt_number=10,
	   wait_exponential_multiplier=300,
	   wait_exponential_max=1 * 60 * 1000)
def poll_status(_id):
	result = athena.get_query_execution(QueryExecutionId=_id)
	state = result['QueryExecution']['Status']['State']

	if state == 'SUCCEEDED':
		return result
	elif state == 'FAILED':
		return result
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

	QueryExecutionId = response['QueryExecutionId']
	result = poll_status(QueryExecutionId)

	if result['QueryExecution']['Status']['State'] == 'SUCCEEDED':
		logging.info(f"Query SUCCEEDED: {QueryExecutionId}")

		output_file = QueryExecutionId + '.csv'

		return output_file
