terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  type = string
}

variable "context_id" {
  type        = string
  description = "Unique identifier for this context (e.g., jsmith, jsmith_dev, teamA_test, prod)"
}

# Locals for naming and tagging
locals {
  resource_prefix = var.context_id
  common_tags = {
    Context   = var.context_id
    Project   = "word-counter"
    ManagedBy = "terraform"
  }
}

# S3 bucket for word count results
resource "aws_s3_bucket" "results" {
  bucket = "${local.resource_prefix}-word-counter-results"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "cleanup_old_files"
    status = "Enabled"
    
    expiration {
      days = 30  # Automatically delete files after 30 days
    }
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${local.resource_prefix}-word-counter-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda" {
  name = "${local.resource_prefix}-word-counter-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.results.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "word_counter" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${local.resource_prefix}-word-counter"
  role            = aws_iam_role.lambda.arn
  handler         = "word_counter.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.results.id
    }
  }

  tags = local.common_tags
}

# Create ZIP file for Lambda
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../src/word_counter.py"
  output_path = "${path.module}/../build/lambda.zip"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.resource_prefix}-word-counter"
  retention_in_days = 30
  tags             = local.common_tags
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "api" {
  name          = "${local.resource_prefix}-word-counter"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
  }

  tags = local.common_tags
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId    = "$context.requestId"
      ip          = "$context.identity.sourceIp"
      requestTime = "$context.requestTime"
      httpMethod  = "$context.httpMethod"
      routeKey    = "$context.routeKey"
      status      = "$context.status"
      protocol    = "$context.protocol"
      responseLength = "$context.responseLength"
      integration = {
        error     = "$context.integration.error"
        status    = "$context.integration.status"
        latency   = "$context.integration.latency"
      }
    })
  }

  tags = local.common_tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.resource_prefix}-word-counter"
  retention_in_days = 30
  tags             = local.common_tags
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.word_counter.invoke_arn
  payload_format_version = "2.0"
}

# API Gateway route
resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /analyze"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.word_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# Outputs
output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "${aws_apigatewayv2_stage.api.invoke_url}analyze"
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.word_counter.function_name
}

output "bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.results.id
}

output "log_group_lambda" {
  description = "CloudWatch Log Group for Lambda"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "log_group_api" {
  description = "CloudWatch Log Group for API Gateway"
  value       = aws_cloudwatch_log_group.api.name
}
