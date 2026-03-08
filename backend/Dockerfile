# FastAPI Backend
# Default image is CPU-oriented. For NVIDIA GPU inference in Docker, use a
# CUDA-capable base image and run the container with NVIDIA Container Toolkit.
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    portaudio19-dev \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies first (for caching)
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# On Linux GPU hosts, replace the default torch install with a CUDA-enabled
# wheel during image build so torch.cuda.is_available() is True in-container.

# Copy backend source code
COPY backend/ .

# Expose FastAPI port
EXPOSE 8000

# Run FastAPI app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
