# Serverless Word Counter

A serverless application that analyzes text frequency and provides download links for results.

Most importantly a POC to demonstrate the complexities behind platform engineering.

## Project Structure

```
.
├── Makefile
├── README.md
├── context
│   └── context.tfvars.example
├── requirements.txt
├── scripts
│   ├── cleanup-state.sh
│   ├── cleanup-state.sh.1
│   ├── setup-state.sh
│   └── watch-logs.sh
├── src
│   └── word_counter.py
├── terraform
│   └── main.tf
└── tests
    └── test_api.py
```

## Prerequisites

1. AWS CLI installed and configured
2. Terraform v1.0.0+
3. Python 3.9+
4. Make
5. curl or Postman

## Environment Setup

1. Install Terraform:
```bash
# Follow instructions at https://learn.hashicorp.com/tutorials/terraform/install-cli
```

2. Install AWS CLI and configure credentials:
```bash
aws configure
export AWS_PROFILE={your profile}
```

3. Configure Initial variables and state management setup
```bash
cp context/context.tfvars.example context/context.tfvars
# Edit context/context.tfvars with your values

# Create state management infrastructure (S3 persistent terraform state)
make setup-state
```

4. Create Python virtual environment:
```bash
python -m venv venv
source venv/bin/activate
```

## Security Features

- S3 bucket with public access blocked
- IAM roles with least privilege
- 7-day file expiration lifecycle policy
- Pre-signed URLs with 1-hour expiration
- Environment (Context) separation for resources

## Deployment

```bash
# Install dependencies
make install

# Initialize Terraform with your state configuration
export AWS_PROFILE={your profile}
make init

# See what will be created
make plan

# Deploy the infrastructure
make apply

# Test the deployment
make test
```

## Testing with curl
```bash
# Test with curl
curl -X POST \
  $(cd terraform && terraform output -raw api_endpoint) \
  -H "Content-Type: application/json" \
  -d '{"text": "This is a test text. This text will help us test the word counter. The counter should count the most frequent words in this test text."}'
```

The output will be something like the below:
```
{"download_url": "https://nurquiza-word-counter-results.s3.amazonaws.com/word_counts_20241123_063857_4f89c91e-7dc4-4792-93b1-47fc7e03ee28.json?AWSAccessKeyId=ASIA4YNWJKE42EJFJ6UB&Signature=tVfP%2B8UfaZV0h0rdU3yL%2BbHqii8%3D&x-amz-security-token=IQoJb3JpZ2luX2VjEDcaCXVzLXdlc3QtMiJGMEQCIDMBYig5FyDPMNWHOPdQeDs8oioxWIzzBTqjWfP9PvRbAiAPrF3eusDhVX91uG2loR1vdnCr68Y0wX4n6gET1sxGGiqHAwjQ%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F8BEAAaDDg3NzA5MjQ5MTU3NyIM%2FEXXbIsMrk9CSAW3KtsC7iyJutjQEZauuva1gDNlYdF3Y6Ls3Uz509uOfdZrj4UqlSdEUYGKGSCwZhNzwWTh21PM6%2FRRtOxEFAMpfiJcKyJeuRa2SB0r4LZrzvHXHeHraD23syPp5IHV6qMPXxPKR6Ywsv3hci3YfvTOsW2ZbyNWdFiG9ufDnIjg8f6SWQLXzqyzH9PdIEdyBAoifczFIyKcjpAKkFgeECfRr5elTJuOfVSYtodLx7U33HASZXdL%2FmYB%2B%2FH3Do9k8BVGtzSVxMCVEe181xZ42LEJ2iUD17JT9fbCxhGc0ZLQyHj7q%2F5IfFVhIAN4KShbu%2BQTkz%2BXSQKmFP38jJwR%2FIVPekKXsmw4k%2BDqsTNc3C3VSlYXgi3zkXDHHAsxpqLHxd18qECPuyWUzwJEQ8HiIZHmccg4BAS%2BgWB%2FcG3%2BX6Hd3ibvjHMkFiF0VPayfCVyNaet3uaUizoPmDqE3c0JTlcwgPGFugY6nwF9tjIASa8E%2FNm%2Fdha7%2FMK5Al04JF4WNOAXNm5BR%2Bp7oW43OwL1X0J1lEEJCQte6BHT8LcqKghbRf6Kbi7umD2naH%2FpSEFaxbvN8jx0dpQDY%2BoY1TQGuFopTXUWpR72F8TScKPZLkvCKDLbGPfoXCoBO2KjWvugjg7%2BD464UB%2Fxl6K8N2MTgSm3tAdVPD7OaxdKyvTfI9Trxcsx22eMozA%3D&Expires=1732347539", "word_counts": {"this": 3, "test": 3, "text": 3, "the": 3, "counter": 2, "is": 1, "a": 1, "will": 1, "help": 1, "us": 1}}%   
```

The url will show something like the below:
```
{
  "this": 3,
  "test": 3,
  "text": 3,
  "the": 3,
  "counter": 2,
  "is": 1,
  "a": 1,
  "will": 1,
  "help": 1,
  "us": 1
}
```

## Monitoring (view and clean cloudwatch logs)
```bash
# Last 3 hours of Lambda logs
make logs-lambda TIME=3h

# Last day of API logs
make logs-api TIME=1d

# Last week of all logs
make logs TIME=1w

# Cleanup logs in case of any processes are still hanging
make logs-cleanup
```

## Check S3 bucket contents:
```bash
aws s3 ls s3://$(terraform output -raw bucket_name)
```

## Cleanup State Infrastructure
To remove state management infrastructure after you're done:

```bash
# Ensure the results and the state buckets are empty
export CONTEXT_ID=$(awk -F= '/context_id/ {gsub(/"/, "", $2); print $2}' context/context.tfvars | xargs)
aws s3 rm s3://${CONTEXT_ID}-word-counter-results/ --recursive

# First destroy application resources
make destroy

# Then clean up state management infrastructure
make cleanup-state
```

## Listing all resources in the region
To ensure that in your region you have left no lingering resources run the below:
```bash
AWS_REGION=$(awk -F= '/aws_region/ {gsub(/"/, "", $2); print $2}' context/context.tfvars | xargs)
aws resourcegroupstaggingapi get-resources --region $AWS_REGION
```

## Launch next steps
* Set up custom domain in Route53, implement ACM certificate management, configure DNS records and validation
* Add API authentication (API Key or IAM), implement rate limiting, add WAF protection, configure VPC for Lambda (if needed)
* Add monitoring and observability, sSet up CloudWatch alarms for errors and latency, enable X-Ray tracing, implement structured logging, add operational dashboards
* Implement infrastructure pipeline, setup application deployment pipeline, add automated testing stages, configure different environments (dev/staging/prod)
* Configure Lambda concurrency, optimize memory allocation, implement caching strategy, set up performance monitoring
* Implement audit logging, add compliance-required tagging, set up backup procedures, configure retention policies
* Set up cost allocation tags, configure auto-scaling policies, implement resource cleanup procedures, set up cost monitoring

## License

MIT License
