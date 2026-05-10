FROM python:3.12-slim

RUN pip install --no-cache-dir apprise markdown

COPY entrypoint.sh /entrypoint.sh
COPY templates /templates

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
