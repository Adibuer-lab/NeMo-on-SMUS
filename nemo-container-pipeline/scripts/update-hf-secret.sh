#!/bin/bash
# Update Hugging Face access token in Secrets Manager
# Run via: make hf-secret
set -e

SECRET_NAME="nemo-container-build/hf-access-token"
AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "$HF_ACCESS_TOKEN" ]]; then
    echo "ERROR: HF_ACCESS_TOKEN not set"
    echo "Set HF_ACCESS_TOKEN in .env file or run: make hf-secret TOKEN=your-token"
    exit 1
fi

SECRET_VALUE="${HF_ACCESS_TOKEN}"

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
