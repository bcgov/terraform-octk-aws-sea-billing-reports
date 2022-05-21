FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Vancouver
RUN apt-get update && apt-get install -y python3 python3-pip awscli
WORKDIR /app
COPY ./billing-report-utility/* ./
RUN pip3 install -r requirements.txt