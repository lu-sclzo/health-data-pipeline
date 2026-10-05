"""
AWS Health Data Pipeline

Extracts synthetic clinic CSV files from an Amazon S3 raw-data bucket,
applies data-quality and standardization rules with Pandas, and writes
the cleaned datasets to a separate processed-data S3 bucket.

AWS authentication is handled through the environment in which the
application runs, allowing EC2 IAM roles to be used instead of
hard-coded AWS credentials.
"""

import boto3
import pandas as pd
import io
import logging
import os
from datetime import datetime


# Bucket names can be supplied at runtime through environment variables.
# Defaults are provided for the portfolio/demo environment.
RAW_BUCKET = os.environ.get("RAW_BUCKET", "clinic-data-raw-lucas-2026")
PROCESSED_BUCKET = os.environ.get(
    "PROCESSED_BUCKET",
    "clinic-data-processed-lucas-2026"
)


# Configure application logging for pipeline execution and monitoring.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

log = logging.getLogger(__name__)


def get_files_to_process(s3):
    """Return all CSV object keys currently stored in the raw S3 bucket."""

    paginator = s3.get_paginator("list_objects_v2")
    files = []

    # Pagination allows the pipeline to handle buckets containing
    # more objects than a single S3 ListObjectsV2 response can return.
    for page in paginator.paginate(Bucket=RAW_BUCKET):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".csv"):
                files.append(obj["Key"])

    log.info(f"Found {len(files)} file(s) to process")
    return files


def read_csv(s3, key):
    """Download a raw CSV object from S3 and load it into a DataFrame."""

    log.info(f"Reading: s3://{RAW_BUCKET}/{key}")

    response = s3.get_object(
        Bucket=RAW_BUCKET,
        Key=key
    )

    content = response["Body"].read().decode("utf-8")

    return pd.read_csv(io.StringIO(content))


def clean_data(df):
    """Validate and standardize clinic records before storage."""

    original_rows = len(df)

    # Patient ID is treated as a required identifier. Records without
    # one are removed because they cannot be reliably associated with
    # an individual synthetic patient record.
    df = df.dropna(subset=["patient_id"])

    # Normalize visit dates into a consistent YYYY-MM-DD format.
    # Invalid date values are converted to missing values.
    df["visit_date"] = pd.to_datetime(
        df["visit_date"],
        errors="coerce"
    ).dt.strftime("%Y-%m-%d")

    # Convert age to a numeric field. Missing or invalid values use -1
    # so they remain identifiable for downstream data-quality review.
    df["age"] = pd.to_numeric(
        df["age"],
        errors="coerce"
    ).fillna(-1).astype(int)

    # Normalize diagnosis codes to consistent uppercase values and
    # remove leading/trailing whitespace.
    df["diagnosis_code"] = (
        df["diagnosis_code"]
        .str.upper()
        .str.strip()
    )

    # Normalize ZIP codes to a five-character representation.
    df["zip_code"] = (
        df["zip_code"]
        .astype(str)
        .str.zfill(5)
        .str[:5]
    )

    # Add processing metadata so transformed records include an
    # auditable timestamp indicating when the ETL step occurred.
    df["processed_at"] = datetime.utcnow().isoformat()

    dropped = original_rows - len(df)

    log.info(
        f"Cleaned {original_rows} rows -> {len(df)} rows "
        f"({dropped} dropped)"
    )

    return df


def write_csv(s3, df, output_key):
    """Serialize cleaned data and upload it to the processed S3 layer."""

    buffer = io.StringIO()
    df.to_csv(buffer, index=False)

    s3.put_object(
        Bucket=PROCESSED_BUCKET,
        Key=output_key,
        Body=buffer.getvalue().encode("utf-8"),
        ContentType="text/csv"
    )

    log.info(f"Written: s3://{PROCESSED_BUCKET}/{output_key}")


def main():
    """Run the end-to-end S3 extraction, transformation, and load process."""

    log.info("=== Health Data Pipeline Starting ===")

    # Boto3 automatically uses credentials supplied by the execution
    # environment, including an attached EC2 IAM role when deployed to EC2.
    s3 = boto3.client("s3")

    files = get_files_to_process(s3)

    success = 0
    failed = 0

    # Process files independently so one malformed file does not prevent
    # the remaining raw datasets from being transformed.
    for key in files:
        try:
            df = read_csv(s3, key)
            cleaned = clean_data(df)

            output_key = key.replace(".csv", "_cleaned.csv")

            write_csv(s3, cleaned, output_key)
            success += 1

        except Exception as e:
            log.error(f"FAILED: {key} — {e}")
            failed += 1

    log.info(
        f"=== Done: {success} succeeded, {failed} failed ==="
    )


if __name__ == "__main__":
    main()
