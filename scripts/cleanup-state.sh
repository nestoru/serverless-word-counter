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

echo "WARNING: This will delete all Terraform state management infrastructure for:"
echo "Context ID: ${CONTEXT_ID}"
echo "Region: ${AWS_REGION}"
echo
echo "This action cannot be undone. Type 'yes' to continue:"
read -r response

if [ "$response" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Remove API Gateway resources using resourcegroupstaggingapi
echo "Searching for API Gateway resources tagged with Context=${CONTEXT_ID}..."
RESOURCES=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Context,Values=${CONTEXT_ID}" \
    --resource-type-filters "apigateway" \
    --region "$AWS_REGION" \
    --query "ResourceTagMappingList[].ResourceARN" \
    --output text || echo "")

if [ -n "$RESOURCES" ]; then
    for RESOURCE_ARN in $RESOURCES; do
        echo "Processing ARN: $RESOURCE_ARN"
        # Escape the dollar sign in $default
        RESOURCE_ARN_ESCAPED=$(echo "$RESOURCE_ARN" | sed 's/\$/\\$/g')

        # Extract the resource path from the ARN
        RESOURCE_PATH=$(echo "$RESOURCE_ARN_ESCAPED" | cut -d':' -f6 | sed 's|^/||')
        # Split the resource path into its components
        IFS='/' read -r -a RESOURCE_PARTS <<< "$RESOURCE_PATH"

        RESOURCE_TYPE="${RESOURCE_PARTS[0]}"

        if [[ "${RESOURCE_TYPE}" == "apis" ]] && [[ "${RESOURCE_PARTS[2]}" == "stages" ]]; then
            # This is an HTTP API Stage (V2)
            API_ID="${RESOURCE_PARTS[1]}"
            STAGE_NAME="${RESOURCE_PARTS[3]}"

            echo "Found HTTP API Stage: $STAGE_NAME for API ID: $API_ID"

            # Handle $default stage name
            if [[ "$STAGE_NAME" == '$default' ]]; then
                ESCAPED_STAGE_NAME='\$default'
            else
                ESCAPED_STAGE_NAME="$STAGE_NAME"
            fi

            # Attempt to delete the Stage
            if aws apigatewayv2 get-stage --api-id "$API_ID" --stage-name "$ESCAPED_STAGE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "Deleting Stage: $STAGE_NAME for API ID: $API_ID"
                aws apigatewayv2 delete-stage --api-id "$API_ID" --stage-name "$ESCAPED_STAGE_NAME" --region "$AWS_REGION" || echo "Failed to delete Stage $STAGE_NAME for API ID $API_ID."
            else
                echo "Stage $STAGE_NAME or API $API_ID does not exist. Skipping."
            fi

            # Attempt to delete the API
            if aws apigatewayv2 get-api --api-id "$API_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
                echo "Deleting HTTP API Gateway (V2): $API_ID"
                aws apigatewayv2 delete-api --api-id "$API_ID" --region "$AWS_REGION" || echo "Failed to delete HTTP API Gateway $API_ID."
            else
                echo "API $API_ID does not exist. Skipping."
            fi
        else
            echo "Resource is not an API Stage. Skipping ARN: $RESOURCE_ARN"
        fi
    done
else
    echo "No API Gateway resources found for Context=${CONTEXT_ID}."
fi

# Re-check if any resources remain due to known AWS issue
echo "Re-checking for any remaining API Gateway resources..."
REMAINING_RESOURCES=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Context,Values=${CONTEXT_ID}" \
    --resource-type-filters "apigateway" \
    --region "$AWS_REGION" \
    --query "ResourceTagMappingList[?ResourceARN!=''].ResourceARN" \
    --output text || echo "")

if [ -n "$REMAINING_RESOURCES" ]; then
    echo
    echo "Please note that, currently, this is a known issue with Resource Groups Tagging,"
    echo "where stale or deleted resource tags are still being returned when calling get-resources."
    echo "You may contact AWS Support to report this issue if the resources persist."
    echo
fi

# Check if S3 bucket exists
BUCKET_NAME="${CONTEXT_ID}-terraform-state"
echo "Checking if bucket exists: $BUCKET_NAME"
if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null; then
    echo "Deleting all versions and markers in the bucket: $BUCKET_NAME"

    # Delete all object versions
    VERSIONS=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query "Versions[].{Key:Key,VersionId:VersionId}" --output text || echo "")
    if [ -n "$VERSIONS" ]; then
        echo "$VERSIONS" | while read -r Key VersionId; do
            if [ -n "$Key" ] && [ -n "$VersionId" ]; then
                echo "Deleting object $Key version $VersionId"
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$Key" --version-id "$VersionId" --region "$AWS_REGION"
            fi
        done
    else
        echo "No object versions found in bucket."
    fi

    # Delete all delete markers
    DELETE_MARKERS=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$AWS_REGION" --query "DeleteMarkers[].{Key:Key,VersionId:VersionId}" --output text || echo "")
    if [ -n "$DELETE_MARKERS" ]; then
        echo "$DELETE_MARKERS" | while read -r Key VersionId; do
            if [ -n "$Key" ] && [ -n "$VersionId" ]; then
                echo "Deleting delete marker $Key version $VersionId"
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$Key" --version-id "$VersionId" --region "$AWS_REGION"
            fi
        done
    else
        echo "No delete markers found in bucket."
    fi

    # Delete the bucket
    echo "Deleting the bucket: $BUCKET_NAME"
    aws s3 rb "s3://$BUCKET_NAME" --force --region "$AWS_REGION"
else
    echo "Bucket $BUCKET_NAME does not exist. Skipping."
fi

# Check if DynamoDB table exists
DYNAMODB_TABLE="${CONTEXT_ID}-terraform-locks"
echo "Checking if DynamoDB table exists: $DYNAMODB_TABLE"
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" 2>/dev/null; then
    echo "Deleting DynamoDB table: $DYNAMODB_TABLE"
    aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
else
    echo "DynamoDB table $DYNAMODB_TABLE does not exist. Skipping."
fi

echo "State management infrastructure cleanup completed successfully!"

