FROM ghcr.io/openclaw/openclaw:latest

# 复制 Python qq-client
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY qq_client/ /app/qq_client/

COPY config.toml /app/config.toml

RUN mkdir -p /app/data

ENV OPENCLAW_SERVICE_KIND=gateway

WORKDIR /app
