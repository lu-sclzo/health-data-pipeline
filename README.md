AWS Health Data Pipeline Project

This is a hands-on AWS project I built to simulate a health-data processing pipeline similar to infrastructure used for public-sector/health-data workloads.

I created separate Amazon S3 raw and processed data layers, configured private access, encryption and versioning controls, and used IAM roles so the application could access AWS resources without hard-coded AWS credentials.

I built a Python/Pandas ETL pipeline that reads synthetic clinic data from S3, validates and cleans the records, standardizes fields, and writes the transformed dataset into a processed S3 bucket.

I then containerized the pipeline with Docker and ran it on Amazon EC2. I also rebuilt the infrastructure using Terraform, including S3, IAM, EC2, security groups, and CloudWatch resources, and verified Terraform idempotency before destroying the infrastructure through Terraform.

For CI/CD, I connected the project to GitHub Actions and Docker Hub. A GitHub workflow tests the Python code with Flake8, builds the Docker image, pushes it to Docker Hub, and deploys it to EC2. I troubleshot several real deployment issues along the way, including IAM permissions, EC2 networking/SSH access, Terraform instance compatibility, and CI/CD failures.

Finally, I integrated Amazon CloudWatch Logs with the Docker workload, created a metric filter for pipeline failures, configured a CloudWatch alarm, and connected it to Amazon SNS for email notifications. I manually triggered the alarm and successfully received the alert.

Tech used: AWS S3 • EC2 • IAM • CloudWatch • SNS • Terraform • Docker • GitHub Actions • Python • Pandas • Boto3 • Git • Linux

The final flow was essentially:

Raw S3 → EC2/Docker → Python ETL → Processed S3 → CloudWatch → SNS alerts

All patient/clinic information used for testing was synthetic.
