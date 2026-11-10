FROM python:3.11-slim-trixie
ENV TZ=America/Vancouver
# Apply OS security fixes and remove the CLI affected by CVE-2025-69720.
RUN apt-get update && apt-get upgrade -y \
    && rm -f /usr/bin/infocmp
WORKDIR /app
COPY ./billing-report-utility/ ./
RUN pip3 install -r requirements.txt \
    && pip3 uninstall --yes setuptools pip
