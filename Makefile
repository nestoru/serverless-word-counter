.PHONY: init plan apply destroy test install clean

# Variables derived from context
CONTEXT_ID := $(shell awk -F= '/context_id/ {gsub(/"/, "", $$2); print $$2}' context/context.tfvars | xargs)
AWS_REGION := $(shell awk -F= '/aws_region/ {gsub(/"/, "", $$2); print $$2}' context/context.tfvars | xargs)

# Install dependencies
install:
	pip install -r requirements.txt

# Create build directory
create-build:
	mkdir -p build

# Check for required context
check-context:
	@test -f context/context.tfvars || \
		(echo "Error: context/context.tfvars not found. Copy context/context.tfvars.example and update values" && exit 1)

# Initialize Terraform
init: check-context create-build
	cd terraform && \
	terraform init \
		-backend-config="bucket=$(CONTEXT_ID)-terraform-state" \
		-backend-config="dynamodb_table=$(CONTEXT_ID)-terraform-locks" \
		-backend-config="region=$(AWS_REGION)" \
		-backend-config="key=word-counter/terraform.tfstate"

# Plan changes
plan: check-context create-build
	cd terraform && terraform plan -var-file="../context/context.tfvars"

# Apply changes
apply: check-context create-build
	cd terraform && terraform apply -var-file="../context/context.tfvars" -auto-approve
	@echo "API Endpoint:"
	@cd terraform && terraform output api_endpoint

# Destroy application resources
destroy: check-context
	cd terraform && terraform destroy -var-file="../context/context.tfvars" -auto-approve

# Run tests against deployed endpoint
test: check-context
	@cd terraform && API_ENDPOINT=$$(terraform output -raw api_endpoint) python ../tests/test_api.py

# Clean local files
clean:
	rm -rf build/
	rm -rf terraform/.terraform/
	rm -f terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate*

# Setup state management infrastructure
setup-state: check-context
	@chmod +x scripts/setup-state.sh
	@./scripts/setup-state.sh

# Cleanup state management infrastructure
cleanup-state: check-context
	@chmod +x scripts/cleanup-state.sh
	@./scripts/cleanup-state.sh

# Extended logging options
# TIME can be: 1h, 3h, 1d, 3d, 1w
TIME ?= 1h

logs-lambda: check-context
	@echo "Fetching Lambda logs for last $(TIME)..."
	@cd terraform && aws logs tail $$(terraform output -raw log_group_lambda) \
		--since $(TIME) \
		--follow

logs-api: check-context
	@echo "Fetching API Gateway logs for last $(TIME)..."
	@cd terraform && aws logs tail $$(terraform output -raw log_group_api) \
		--since $(TIME) \
		--follow

logs: check-context
	@echo "Fetching all logs for last $(TIME)..."
	@chmod +x scripts/watch-logs.sh
	@./scripts/watch-logs.sh $(TIME)

# Kill any hanging log processes
logs-cleanup:
	@echo "Cleaning up log monitoring processes..."
	@pkill -f "aws logs tail.*--follow" 2>/dev/null || true
