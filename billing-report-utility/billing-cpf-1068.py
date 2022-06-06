import json
import os
import sys
import logging
import requests

from datetime import date, datetime, timezone, timedelta, tzinfo
from dateutil.relativedelta import *
from fiscalyear import FiscalMonth, FiscalQuarter, setup_fiscal_calendar

from BillingManager import BillingManager

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
logger.addHandler(handler)

setup_fiscal_calendar(start_month=4)


'''
Fiscal week begins Wednesday at 00:00:00 and ends the following Tuesday night
at 23:59:59.

EventBridge schedule is set to trigger the weekly report function on Thursday
of each week. The generated report is meant to be for the previous fiscal week
e.g.: EventBridge trigger on Thur, Jun 02, 2022 should generate report for the
period beginning 00:00:00 Wed, May 25, 2022 through 23:59:59 Tue May 31, 2022
'''


def weekly(event_bridge_params):
	logger.info(f"Called weekly function")
	logger.info(f"event_bridge_params_original: {event_bridge_params}\n")

	# Get today's min (00:00:00) and max (23:59:59) time
	start_date_min = datetime.combine(date.today(), datetime.min.time())
	end_date_max = datetime.combine(date.today(), datetime.max.time())

	# Set start_date to start of Wed the previous week
	start_date = start_date_min + relativedelta(weekday=WE(-2))

	# Set end_date to end of Tue the current week
	end_date = end_date_max + relativedelta(weekday=TU(-1))

	event_bridge_params.update({
		"carbon_copy": None,
		"billing_groups": None,
		"start_date": start_date,
		"end_date": end_date
	})

	logger.info(f"event_bridge_params_updated: {event_bridge_params}\n")

	bill_manager = BillingManager(event_bridge_params)
	bill_manager.do()


'''
EventBridge schedule is set to trigger the monthly report function on the first
day of each month. The generated report is meant to be for the previous month
e.g.: EventBridge trigger on Feb 01 should generate report for Jan 01.
'''


def monthly(event_bridge_params):
	logger.info(f"Called monthly function")
	logger.info(f"event_bridge_params: {json.dumps(dict(event_bridge_params))}")

	previous_fiscal_month_start = FiscalMonth.current().prev_fiscal_month.start.strftime("%Y, %m, %d, %H, %M, %S")
	previous_fiscal_month_end = FiscalMonth.current().prev_fiscal_month.end.strftime("%Y, %m, %d, %H, %M, %S")

	start_date = datetime.strptime(previous_fiscal_month_start, "%Y, %m, %d, %H, %M, %S")
	end_date = datetime.strptime(previous_fiscal_month_end, "%Y, %m, %d, %H, %M, %S")

	event_bridge_params.update({
		"carbon_copy": None,
		"billing_groups": None,
		"start_date": start_date,
		"end_date": end_date
	})
	logger.info(f"event_bridge_params_updated: {event_bridge_params}\n")

	bill_manager = BillingManager(event_bridge_params)
	bill_manager.do()


'''
EventBridge schedule is set to trigger the quarterly report function on the first
day of each quarter. The generated report is meant to be for the previous quarter
e.g.: EventBridge trigger at start of Q1 2022 should generate report for Q4 2021.

Fiscal year begins April 01 of the calendar year. As a result, the second quarter 
of the calendar year is the first quarter of the fiscal year. The mapping between
calendar quarter and fiscal quarter is as follows:

Calendar Q1 <--> Fiscal Q4 <--> Jan - Mar 
Calendar Q2 <--> Fiscal Q1 <--> Apr - Jun
Calendar Q3 <--> Fiscal Q2 <--> Jul - Sep
Calendar Q4 <--> Fiscal Q3 <--> Oct - Dec
'''


def quarterly(event_bridge_params):
	logger.info(f"Called quarterly function")
	logger.info(f"event_bridge_params: {json.dumps(dict(event_bridge_params))}\n")

	previous_fiscal_quarter_start = FiscalQuarter.current().prev_fiscal_quarter.start.strftime("%Y, %m, %d, %H, %M, %S")
	previous_fiscal_quarter_end = FiscalQuarter.current().prev_fiscal_quarter.end.strftime("%Y, %m, %d, %H, %M, %S")

	start_date = datetime.strptime(previous_fiscal_quarter_start, "%Y, %m, %d, %H, %M, %S")
	end_date = datetime.strptime(previous_fiscal_quarter_end, "%Y, %m, %d, %H, %M, %S")

	event_bridge_params.update({
		"carbon_copy": None,
		"billing_groups": None,
		"start_date": start_date,
		"end_date": end_date
	})
	logger.info(f"event_bridge_params_updated: {event_bridge_params}\n")

	bill_manager = BillingManager(event_bridge_params)
	bill_manager.do()


# TODO: Move below comments to README
''' 
Used to generate report for a specific date/time period. This function will not be associated
with an EventBridge target. Executing this function requires credentials from the corresponding
LZ Operations account and the following environment variables:

REPORT_TYPE="Manual"
START_DATE=<YYYY, M, D> - Python datetime format: "%Y, %m, %d" - " eg: "2022, 4, 12"
END_DATE=<YYYY, M, D> - Python datetime format: "%Y, %m, %d" - eg: "2022, 4, 26"
DELIVER=True|False
RECIPIENT_OVERRIDE="hello.123@localhost"
ATHENA_QUERY_ROLE_TO_ASSUME_ARN="arn:aws:iam::<LZ#-ManagementAccountID>:role/BCGov-Athena-Cost-and-Usage-Report"
ATHENA_QUERY_DATABASE="athenacurcfn_cost_and_usage_report"
QUERY_ORG_ACCOUNTS_ROLE_TO_ASSUME_ARN="arn:aws:iam::<LZ#-ManagementAccountID>:role/BCGov-Query-Org-Accounts"
ATHENA_QUERY_OUTPUT_BUCKET="bcgov-ecf-billing-reports-output-<LZ#-ManagementAccountID>-ca-central-1"
ATHENA_QUERY_OUTPUT_BUCKET_ARN="arn:aws:s3:::bcgov-ecf-billing-reports-output-<LZ#-ManagementAccountID>-ca-central-1"
CMK_SSE_KMS_ALIAS="arn:aws:kms:ca-central-1:<LZ#-ManagementAccountID>:alias/BCGov-BillingReports"
'''


def manual(event_bridge_params):
	logger.info(f"Called manual function")
	logger.info(f"event_bridge_params: {json.dumps(dict(event_bridge_params))}\n")

	start_date_env_var = datetime.strptime(os.environ["START_DATE"], "%Y, %m, %d")
	end_date_env_var = datetime.strptime(os.environ["END_DATE"], "%Y, %m, %d")

	start_date = datetime.combine(start_date_env_var, datetime.min.time())
	end_date = datetime.combine(end_date_env_var, datetime.max.time())

	event_bridge_params.update({
		"carbon_copy": None,
		"billing_groups": None,
		"start_date": start_date,
		"end_date": end_date
	})
	logger.info(f"event_bridge_params_updated: {event_bridge_params}\n")

	bill_manager = BillingManager(event_bridge_params)
	bill_manager.do()


def main():
	print("Cloud Pathfinder Billing Utility!")

	logger.info(f"Environment Variables: {json.dumps(dict(os.environ))}")

	if os.environ.get("AWS_EXECUTION_ENV"):
		metadata_uri_v4 = os.environ["ECS_CONTAINER_METADATA_URI_V4"]
		get_v4_metadata = requests.get(format(metadata_uri_v4))
		v4_metadata = get_v4_metadata.json()
		logger.info(f"V4 Metadata: {json.dumps(v4_metadata)}")

	event_bridge_payload = {
		"report_type": os.environ["REPORT_TYPE"].lower(),
		"deliver": bool(os.environ["DELIVER"]),
		"recipient_override": os.environ["RECIPIENT_OVERRIDE"].lower()
	}
	logger.info(f"event_bridge_payload: {json.dumps(dict(event_bridge_payload))}")

	globals()[event_bridge_payload['report_type']](event_bridge_payload)


if __name__ == "__main__":
	main()
