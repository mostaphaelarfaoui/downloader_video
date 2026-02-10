# Use Python base image
FROM python:3.11-slim

# Install FFmpeg (required for yt-dlp format merging)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy dependency list first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Create downloads folder (legacy support)
RUN mkdir -p downloads

# Default environment
ENV PORT=10000
ENV ALLOWED_ORIGINS="*"

# Run the app — Render sets PORT automatically
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port $PORT"]