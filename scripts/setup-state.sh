#!/bin/bash
set -e

# Check if context file exists
if [ ! -f "context/context.tfvars" ]; then
    echo "Error: context/context.tfvars not found"
    exit 1
fi

# Read variables from context
CONTEXT_ID=$(awk -F= '/context_id/ {gsub(/"/, "", $2); print $2}' context/context.tfvars | xargs)
AWS_REGION=$(awk -F= '/aws_region/ {gsub(/"/, "", $2); print $2}' context/context.tfvars | xargs)

echo "Setting up Terraform state management for:"
echo "Context ID: ${CONTEXT_ID}"
echo "Region: ${AWS_REGION}"

# Create S3 bucket
echo "Checking/Creating S3 bucket..."
if aws s3api head-bucket --bucket "${CONTEXT_ID}-terraform-state" 2>/dev/null; then
    echo "Bucket already exists and you own it. Skipping creation."
else
    aws s3api create-bucket \
        --bucket "${CONTEXT_ID}-terraform-state" \
        --region ${AWS_REGION} \
        --create-bucket-configuration LocationConstraint=${AWS_REGION}
    echo "Bucket created successfully."
fi

# Enable versioning
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "${CONTEXT_ID}-terraform-state" \
    --versioning-configuration Status=Enabled

# Enable encryption
echo "Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket "${CONTEXT_ID}-terraform-state" \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# Block public access
echo "Blocking public access..."
aws s3api put-public-access-block \
    --bucket "${CONTEXT_ID}-terraform-state" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table
echo "Checking/Creating DynamoDB table..."
if aws dynamodb describe-table --table-name "${CONTEXT_ID}-terraform-locks" --region ${AWS_REGION} 2>/dev/null; then
    echo "DynamoDB table already exists. Skipping creation."
else
    aws dynamodb create-table \
        --table-name "${CONTEXT_ID}-terraform-locks" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region ${AWS_REGION}
    echo "DynamoDB table created successfully."
fi

echo "State management infrastructure setup completed!"
