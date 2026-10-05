# ============================================================
# AWS Health Data Pipeline - Infrastructure as Code
# ============================================================
# This Terraform configuration provisions the AWS infrastructure
# used by the containerized health-data ETL pipeline.
#
# Architecture:
# Raw S3 -> EC2 / Docker ETL -> Processed S3
#
# IAM provides role-based AWS access, while CloudWatch provides
# centralized logging for pipeline monitoring.
# ============================================================


# ── Terraform / AWS Provider ─────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Deploy all resources into the AWS region supplied through variables.
provider "aws" {
  region = var.aws_region
}


# ── S3 Buckets ───────────────────────────────────────────────

# Raw data layer used to store incoming synthetic clinic datasets
# before they are validated and transformed by the ETL pipeline.
resource "aws_s3_bucket" "raw" {
  bucket = "${var.project_name}-raw-${var.unique_suffix}"

  tags = {
    Name    = "Raw Health Data"
    Project = var.project_name
  }
}

# Processed data layer used to store cleaned and standardized
# clinic datasets produced by the ETL pipeline.
resource "aws_s3_bucket" "processed" {
  bucket = "${var.project_name}-processed-${var.unique_suffix}"

  tags = {
    Name    = "Processed Health Data"
    Project = var.project_name
  }
}

# Block all public access to the raw health-data bucket.
# Objects are accessed only through authorized AWS identities.
resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Encrypt raw health-data objects at rest using Amazon S3
# server-side encryption with AES-256.
resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable object versioning to help protect raw datasets against
# accidental overwrites or deletions.
resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}


# ── IAM Role ─────────────────────────────────────────────────

# IAM role assumed by the EC2 instance running the ETL workload.
# This avoids storing long-lived AWS credentials inside the
# application or Docker image.
resource "aws_iam_role" "pipeline" {
  name = "${var.project_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

# Apply least-privilege permissions required by the pipeline:
# - Read source data from the raw S3 bucket
# - Write transformed data to the processed S3 bucket
# - Publish application logs to CloudWatch
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-pipeline-access"
  role = aws_iam_role.pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]

        Resource = [
          aws_s3_bucket.raw.arn,
          "${aws_s3_bucket.raw.arn}/*"
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "s3:PutObject"
        ]

        Resource = "${aws_s3_bucket.processed.arn}/*"
      },
      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "*"
      }
    ]
  })
}

# Attach the pipeline IAM role to EC2 through an instance profile.
resource "aws_iam_instance_profile" "pipeline" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.pipeline.name
}


# ── Networking ────────────────────────────────────────────────

# Retrieve the account's default VPC for the project environment.
data "aws_vpc" "default" {
  default = true
}

# Security group for the pipeline EC2 instance.
# SSH access is restricted to the administrator IP supplied
# through Terraform variables rather than exposed publicly.
resource "aws_security_group" "pipeline" {
  name   = "${var.project_name}-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  # Permit outbound traffic so the instance can communicate with
  # AWS services and retrieve required container dependencies.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ── EC2 Instance ──────────────────────────────────────────────

# Retrieve the current Amazon Linux AMI through AWS Systems
# Manager Parameter Store instead of hard-coding an AMI ID.
data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# EC2 compute layer used to execute the containerized ETL workload.
# AWS permissions are supplied through the attached IAM instance
# profile rather than hard-coded application credentials.
resource "aws_instance" "processor" {
  ami                    = data.aws_ssm_parameter.amazon_linux.value
  instance_type          = "t3.micro"
  key_name               = "HealthPipelineKey"
  vpc_security_group_ids = [aws_security_group.pipeline.id]
  iam_instance_profile   = aws_iam_instance_profile.pipeline.name

  tags = {
    Name = "${var.project_name}-processor"
  }
}


# ── CloudWatch Log Group ──────────────────────────────────────

# Centralized CloudWatch log group for pipeline monitoring.
# Logs are retained for 30 days to balance observability with
# storage lifecycle management.
resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/${var.project_name}"
  retention_in_days = 30
}
