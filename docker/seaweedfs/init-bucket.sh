#!/bin/sh
# -----------------------------------------------------------------------------
# Idempotently creates the initial S3 bucket on the SeaweedFS gateway.
# Designed to run as a one-shot Docker Compose service against an `aws-cli`
# image. Retries with exponential backoff while the gateway warms up.
# -----------------------------------------------------------------------------
set -eu

: "${S3_ENDPOINT:?S3_ENDPOINT must be set (e.g. http://seaweedfs-s3:8333)}"
: "${S3_BUCKET:?S3_BUCKET must be set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"
: "${AWS_DEFAULT_REGION:=us-east-1}"
export AWS_DEFAULT_REGION

MAX_ATTEMPTS=${MAX_ATTEMPTS:-8}
attempt=1
delay=1

aws_s3() {
    aws --endpoint-url "$S3_ENDPOINT" s3api "$@"
}

while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    if aws_s3 head-bucket --bucket "$S3_BUCKET" >/dev/null 2>&1; then
        echo "Bucket '$S3_BUCKET' already exists. Nothing to do."
        exit 0
    fi

    if aws_s3 create-bucket --bucket "$S3_BUCKET" >/dev/null 2>&1; then
        echo "Bucket '$S3_BUCKET' created."
        exit 0
    fi

    echo "Gateway not ready or transient error (attempt $attempt/$MAX_ATTEMPTS). Sleeping ${delay}s..." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
done

echo "Failed to ensure bucket '$S3_BUCKET' after $MAX_ATTEMPTS attempts." >&2
exit 1
