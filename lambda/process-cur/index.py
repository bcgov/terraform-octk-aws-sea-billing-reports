import os
import sys
import csv
import boto3
import botocore
from retrying import retry

# configuration
s3_bucket = os.environ['S3_BUCKET']       # S3 Bucket name
s3_ouput  = 's3://'+ s3_bucket   # S3 Bucket to store results
database  = os.environ['ATHENA_DATABASE']  # The database to which the query belongs

# init clients
athena = boto3.client('athena')
s3     = boto3.resource('s3')


def handler(event, context):
    # SQL Query to execute
    query = ("""
       SELECT
        line_item_usage_account_id, line_item_product_code, line_item_blended_cost, year, month
        FROM cost_and_usage_report
        WHERE year = '{year}' and month = '{month}'
        and line_item_blended_cost > 0
    """.format(year=event['year'], month=event['month']))

    print("Executing query: {}".format(query))
    result = run_query(query, database, s3_ouput)

    print("Results:")
    print(result)

    return result



@retry(stop_max_attempt_number = 10,
    wait_exponential_multiplier = 300,
    wait_exponential_max = 1 * 60 * 1000)
def poll_status(_id):
    result = athena.get_query_execution( QueryExecutionId = _id )
    state  = result['QueryExecution']['Status']['State']

    print(state)

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
        print("Query SUCCEEDED: {}".format(QueryExecutionId))

        s3_key = QueryExecutionId + '.csv'
        local_filename = s3_ouput + '/' + QueryExecutionId + '.csv'

        return local_filename

