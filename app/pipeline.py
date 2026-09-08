import boto3
import pandas as pd
import io
import logging
import os
from datetime import datetime

RAW_BUCKET = os.environ.get("RAW_BUCKET", "clinic-data-raw-lucas-2026")
PROCESSED_BUCKET = os.environ.get(
    "PROCESSED_BUCKET",
    "clinic-data-processed-lucas-2026"
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)
log = logging.getLogger(__name__)


def get_files_to_process(s3):
    """Get a list of all CSV files in the raw bucket."""
    paginator = s3.get_paginator("list_objects_v2")
    files = []

    for page in paginator.paginate(Bucket=RAW_BUCKET):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".csv"):
                files.append(obj["Key"])

    log.info(f"Found {len(files)} file(s) to process")
    return files


def read_csv(s3, key):
    """Download a CSV file from S3 and load it as a DataFrame."""
    log.info(f"Reading: s3://{RAW_BUCKET}/{key}")
    response = s3.get_object(Bucket=RAW_BUCKET, Key=key)
    content = response["Body"].read().decode("utf-8")
    return pd.read_csv(io.StringIO(content))


def clean_data(df):
    """Apply data quality rules to the DataFrame."""
    original_rows = len(df)

    # Remove records without a patient ID
    df = df.dropna(subset=["patient_id"])

    # Standardize visit dates
    df["visit_date"] = pd.to_datetime(
        df["visit_date"], errors="coerce"
    ).dt.strftime("%Y-%m-%d")

    # Missing age becomes -1
    df["age"] = pd.to_numeric(
        df["age"], errors="coerce"
    ).fillna(-1).astype(int)

    # Standardize diagnosis codes
    df["diagnosis_code"] = (
        df["diagnosis_code"].str.upper().str.strip()
    )

    # Standardize ZIP codes
    df["zip_code"] = (
        df["zip_code"].astype(str).str.zfill(5).str[:5]
    )

    # Processing metadata
    df["processed_at"] = datetime.utcnow().isoformat()

    dropped = original_rows - len(df)
    log.info(
        f"Cleaned {original_rows} rows -> {len(df)} rows "
        f"({dropped} dropped)"
    )

    return df


def write_csv(s3, df, output_key):
    """Write cleaned data to the processed S3 bucket."""
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
    log.info("=== Health Data Pipeline Starting ===")

    s3 = boto3.client("s3")
    files = get_files_to_process(s3)

    success = 0
    failed = 0

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
