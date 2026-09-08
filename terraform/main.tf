terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── S3 Buckets ─────────────────────────────────────────────

resource "aws_s3_bucket" "raw" {
  bucket = "${var.project_name}-raw-${var.unique_suffix}"

  tags = {
    Name    = "Raw Health Data"
    Project = var.project_name
  }
}

resource "aws_s3_bucket" "processed" {
  bucket = "${var.project_name}-processed-${var.unique_suffix}"

  tags = {
    Name    = "Processed Health Data"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── IAM Role ────────────────────────────────────────────────

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

resource "aws_iam_instance_profile" "pipeline" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.pipeline.name
}

# ── Networking ──────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "pipeline" {
  name   = "${var.project_name}-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── EC2 Instance ────────────────────────────────────────────

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

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

# ── CloudWatch Log Group ────────────────────────────────────

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/${var.project_name}"
  retention_in_days = 30
}
