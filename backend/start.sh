#!/bin/sh
set -e

PORT="${PORT:-8080}"

exec gunicorn main:app \
  --workers 1 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind "0.0.0.0:${PORT}" \
  --timeout 120
