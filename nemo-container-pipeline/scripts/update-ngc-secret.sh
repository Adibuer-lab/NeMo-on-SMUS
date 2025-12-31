#!/bin/bash
# Update NGC API key in Secrets Manager
# Run via: make ngc-secret
set -e

SECRET_NAME="nemo-container-build/ngc-api-key"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "$NGC_KEY" ]]; then
    echo "ERROR: NGC_KEY not set"
    echo "Set NGC_KEY in .env file or run: make ngc-secret KEY=your-key"
    exit 1
fi

SECRET_VALUE="{\"username\":\"\$oauthtoken\",\"password\":\"${NGC_KEY}\"}"

# Check if secret exists
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION"
    echo "Updated secret: $SECRET_NAME"
else
    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --secret-string "$SECRET_VALUE" \
        --region "$AWS_REGION"
    echo "Created secret: $SECRET_NAME"
fi
