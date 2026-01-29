FROM python:3.11-slim-bookworm

# Install dependencies
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY main.py .

# Create non-root user
RUN useradd -u 10001 -r -s /bin/false allowlist && \
    mkdir -p /data && \
    chown -R allowlist:allowlist /app /data

USER allowlist

ENTRYPOINT ["python3", "-u", "/app/main.py"]
