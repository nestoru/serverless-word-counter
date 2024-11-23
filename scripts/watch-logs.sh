#!/bin/bash

# Get log group names from terraform outputs
cd terraform
LAMBDA_LOGS=$(terraform output -raw log_group_lambda)
API_LOGS=$(terraform output -raw log_group_api)
cd ..

echo "Starting log monitoring..."
echo "Press Ctrl+C once to stop watching logs"
echo "----------------------------------------"

# Function to watch a log group
watch_logs() {
    local log_group=$1
    local since=$2
    echo "Watching logs for: $log_group"
    aws logs tail "$log_group" --since "$since" --follow &
}

# Handle interrupt gracefully
trap 'echo -e "\nStopping log monitoring..."; kill $(jobs -p) 2>/dev/null; exit' INT

# Start watching both log groups
watch_logs "$LAMBDA_LOGS" "$1"
watch_logs "$API_LOGS" "$1"

# Wait for Ctrl+C
wait
