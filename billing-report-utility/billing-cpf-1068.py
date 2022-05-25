import json
import os
import sys
import logging
import requests

from datetime import date, datetime, timezone, timedelta, tzinfo
# from BillingManager import BillingManager

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(formatter)
logger.addHandler(handler)


def weekly(event_bridge_params):
	logger.info(f"Called weekly function")
	logger.info(f"event_bridge_params_original: {event_bridge_params}\n")

	end_date = datetime.combine(
		(date.today() - timedelta(days=1)), datetime.max.time(), tzinfo=timezone.utc
	)

	start_date = datetime.combine(
		(end_date - timedelta(days=6)), datetime.min.time(), tzinfo=timezone.utc
	)

	event_bridge_params.update({
		"carbon_copy": None,
		"billing_groups": None,
		"start_date": start_date.strftime("%Y, %m, %-d, %-H, %-M, %-S, %f, %Z"),
		"end_date": end_date.strftime("%Y, %m, %-d, %-H, %-M, %-S, %f, %Z")
	})

	logger.info(f"event_bridge_params_updated: {event_bridge_params}\n")

	# bill_manager = BillingManager(event_bridge_params)
	# s3_buckets = bill_manager.query_s3_buckets()
	# logger.info(f"Weekly S3 bucket query: {s3_buckets}")

	# bill_manager = BillingManager(
	# 	event_bridge_params,
	# 	delivery_config=None,
	# 	quarterly_report_config=None
	# )
	# bill_manager.do(existing_file=None)


def monthly(event_bridge_params):
	logger.info(f"Called monthly function")
	logger.info(f"event_bridge_params: {json.dumps(dict(event_bridge_params))}")


def quarterly(event_bridge_params):
	logger.info(f"Called quarterly function")
	logger.info(f"event_bridge_params: {json.dumps(dict(event_bridge_params))}\n")

	start_date = date.today()
	end_date = date.today()

	quarter = ((datetime.now().month - 1) // 3 + 1)

	print(f"Which Quarter: {quarter}\n")

	if quarter == 1:
		start_date = datetime.combine(
			date(datetime.datetime.now().year, 4, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
		end_date = datetime.combine(
			date(datetime.datetime.now().year, 7, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
	elif quarter == 2:
		start_date = datetime.combine(
			date(datetime.now().year, 7, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
		end_date = datetime.combine(
			date(datetime.now().year, 10, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
	elif quarter == 3:
		start_date = datetime.combine(
			date(datetime.now().year, 10, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
		end_date = datetime.combine(
			date(datetime.now().year + 1, 1, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
	elif quarter == 4:
		start_date = datetime.combine(
			date(datetime.now().year, 1, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)
		end_date = datetime.combine(
			date(datetime.now().year, 4, 1),
			datetime.min.time(), tzinfo=timezone.utc
		)

	event_bridge_params.update({
		"carbon_copy": None,
		"billing_groups": None,
		"start_date": start_date.strftime("%Y, %m, %-d, %-H, %-M, %-S, %f, %Z"),
		"end_date": end_date.strftime("%Y, %m, %-d, %-H, %-M, %-S, %f, %Z")
	})

	logger.info(f"event_bridge_params_updated: {json.dumps(dict(event_bridge_params))}\n")

	# bill_manager = BillingManager(
	# 	event_bridge_params,
	# 	delivery_config=None,
	# 	quarterly_report_config=None
	# )
	# bill_manager.do(existing_file=None)


def main():
	print("Cloud Pathfinder Billing Utility!")

	logger.info(f"Environment Variables: {json.dumps(dict(os.environ))}")

	metadata_uri_v4 = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
	get_v4_metadata = requests.get(format(metadata_uri_v4))
	v4_metadata = get_v4_metadata.json()
	logger.info(f"V4 Metadata: {json.dumps(v4_metadata)}")

	event_bridge_payload = {
		"report_type": os.environ.get("REPORT_TYPE").lower(),
		"deliver": bool(os.environ.get("DELIVER")),
		"recipient_override": os.environ.get("RECIPIENT_OVERRIDE").lower()
	}

	report_type = globals()[event_bridge_payload['report_type']](event_bridge_payload)

	# logger.info(f"event_bridge_payload: {json.dumps(dict(event_bridge_payload))}")


if __name__ == "__main__":
	main()
