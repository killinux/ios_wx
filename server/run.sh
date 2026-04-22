#!/bin/sh
set -eu
cd "$(dirname "$0")"

if [ ! -d venv ]; then
    python3 -m venv venv
    ./venv/bin/pip install -r requirements.txt
fi

HOST=${HOST:-0.0.0.0}
PORT=${PORT:-8080}
echo "starting ios_wx server on $HOST:$PORT"
exec ./venv/bin/uvicorn main:app --host "$HOST" --port "$PORT"
