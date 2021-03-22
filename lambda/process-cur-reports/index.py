import os
import io
import sys
import csv
import boto3
import botocore
import pandas as pd
import numpy as np
from jinja2 import Environment, FileSystemLoader
from urllib.parse import urlparse


# configuration
s3_bucket = os.environ['S3_BUCKET']       # S3 Bucket name

# init clients
s3     = boto3.resource('s3')


def handler(event, context):
    
    month = event['month']
    year = event['year']
    local_file = event['local_file']
    accountIds = event['team']['accountIds']
    bu = event['team']['business_unit']
    
    
    # download result file
    print('downloading file from S3...')
    try:
        tmp_index = local_file.rindex('/')
        tmp_filename = '/tmp/' + local_file[tmp_index+1:]
        s3url = urlparse(local_file)
        s3bucket = s3url.netloc
        s3key = s3url.path[1:]
        
        s3.Bucket(s3bucket).download_file(s3key, tmp_filename)
        
        local_file = tmp_filename
                        
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            print("The object does not exist.")
        else:
            raise
    
    if os.path.exists(local_file):
        print("File exists {}".format(local_file))
    else:
        print("The file does not exist")    
        
    
    df = pd.read_csv(local_file)
    pd.set_option('display.float_format', '${:.2f}'.format)
    
    billing_temp = df.query('year == [{year}] and month == [{month}] and (line_item_usage_account_id in {ids})'.format(year=year, month=month, ids=accountIds))
    billing = pd.pivot_table(billing_temp,index=['year', 'month', 'line_item_usage_account_id', 'line_item_product_code' ], values=['line_item_blended_cost'], aggfunc=[np.sum],fill_value=0, margins=True, margins_name='Total')
    
    # debug
    # print(billing)

    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template("report.html")
    
    template_vars = {
        "title" : "AWS Report",
        "pivot_table": billing.to_html(),
        "business_unit": bu
    }
    
    html_out = template.render(template_vars)
    
    report_name = "{year}-{month}-{bu}.html".format(year=year, month=month, bu=bu)
    
    report_file_name = "/tmp/{}".format(report_name)
    
    with open(report_file_name, "w") as text_file:
        text_file.write(html_out)
    
    s3.Bucket(s3_bucket).upload_file(report_file_name, "reports/{}".format(report_name))
