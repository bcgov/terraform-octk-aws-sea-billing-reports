from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import boto3


class EmailDelivery:

	def __init__(self, ):
		self.ses_client = boto3.client("ses", region_name="ca-central-1")

	def send_email(self, sender, recipient, cc=None, bcc=None, subject=None, body_text=None, attachments=None):
		if attachments is None:
			attachments = []
		msg = MIMEMultipart()
		msg["Subject"] = subject
		msg["From"] = sender
		msg["To"] = recipient

		if cc:
			msg['CC'] = cc

		if bcc:
			msg['BCC'] = bcc

		# later we will need to set all destinations. here we quickly make that list
		destinations = [d for d in [recipient, cc, bcc] if d is not None]

		# Set message body
		body = MIMEText(body_text, "plain")
		msg.attach(body)

		if attachments:
			for attachment in attachments:
				with open(attachment, "rb") as my_attachment:
					part = MIMEBase("application", "octet-stream")
					part.set_payload(my_attachment.read())

				# Encode file in ASCII characters to send by email
				encoders.encode_base64(part)

				# header wants just the filename sans path, so extract that
				filename = attachment.split("/")[::-1][0]

				# Add header as key/value pair to attachment part
				part.add_header(
					"Content-Disposition",
					f"attachment; filename= \"{filename}\"",
				)

				msg.attach(part)

		# Convert message to string and send
		return self.ses_client.send_raw_email(
			Source=sender,
			Destinations=destinations,
			RawMessage={"Data": msg.as_string()}
		)


def main():
	emailer = EmailDelivery()
	# email_result =emailer.send_email(sender="info@cloud.gov.bc.ca", recipient="max.wardle@gov.bc.ca", subject="Hello SES!",
	# 								 body_text="Yo yo yo.", attachments="output/1a323611-e4a4-4743-acad-0b9f91249669/reports/2021-06-01-2021-06-30-CPF.html")
	# print(email_result)

	email_result =emailer.send_email(sender="info@cloud.gov.bc.ca", recipient="max.wardle@gov.bc.ca", subject="Hello SES!",
									 body_text="Yo yo yo. (no attachment)")

	print(email_result)


if __name__ == "__main__":
	main()
