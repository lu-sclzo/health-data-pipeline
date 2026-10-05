# Use a lightweight Python 3.11 runtime for the ETL application.
FROM python:3.11-slim

# Set the application directory inside the container.
WORKDIR /app

# Copy dependencies separately to take advantage of Docker layer caching.
COPY requirements.txt .

# Install Python dependencies without retaining the pip cache.
RUN pip install --no-cache-dir -r requirements.txt

# Copy the health-data ETL application into the container.
COPY pipeline.py .

# Run the pipeline when the container starts.
CMD ["python", "pipeline.py"]
