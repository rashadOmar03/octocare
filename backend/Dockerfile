FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# ffmpeg converts browser webm/m4a to 16 kHz mono WAV for accurate Whisper transcription.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Install Python deps first — this layer is cached until requirements.txt changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

# App code + Flutter web bundle (served by FastAPI).
COPY . .

RUN chmod +x start.sh

CMD ["./start.sh"]
