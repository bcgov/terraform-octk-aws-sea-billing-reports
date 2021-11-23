
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y python3 python3-pip
COPY ./billing-report-utility .
RUN pip3 install -r requirements.txt
ENTRYPOINT python3 billing.py $ARGS
