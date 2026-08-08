#!/bin/bash
set -e

OLLAMA_MODELS_DIR="${OLLAMA_MODELS:-/workspace/ollama}"
OPEN_WEBUI_DATA_DIR="${DATA_DIR:-/workspace/open-webui/data}"
LOG_DIR="${LOG_DIR:-/workspace/logs}"
SECRET_FILE="/workspace/open-webui/.webui_secret_key"

mkdir -p "$OLLAMA_MODELS_DIR" "$OPEN_WEBUI_DATA_DIR" "$LOG_DIR"

if [ -z "${WEBUI_SECRET_KEY:-}" ]; then
    if [ ! -s "$SECRET_FILE" ]; then
        mkdir -p "$(dirname "$SECRET_FILE")"
        (umask 077; openssl rand -hex 32 > "$SECRET_FILE")
    fi
    WEBUI_SECRET_KEY=$(<"$SECRET_FILE")
fi
export WEBUI_SECRET_KEY

export OLLAMA_HOST=127.0.0.1:11434
export OLLAMA_MODELS="$OLLAMA_MODELS_DIR"

/usr/bin/ollama serve >>"$LOG_DIR/ollama.log" 2>&1 &
OLLAMA_PID=$!

for attempt in $(seq 1 120); do
    if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null; then
        break
    fi
    if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
        echo "Ollama exited before readiness; see $LOG_DIR/ollama.log" >&2
        exit 1
    fi
    if [ "$attempt" -eq 120 ]; then
        echo "Ollama readiness timed out; see $LOG_DIR/ollama.log" >&2
        exit 1
    fi
    sleep 1
done

env -u PIP_CONSTRAINT \
    DATA_DIR="$OPEN_WEBUI_DATA_DIR" \
    OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    WEBUI_AUTH=True \
    ENABLE_LOGIN_FORM=True \
    UVICORN_WORKERS=1 \
    WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
    /opt/open-webui/venv/bin/open-webui serve --host 0.0.0.0 --port 3000 \
    >>"$LOG_DIR/open-webui.log" 2>&1 &
OPEN_WEBUI_PID=$!

for attempt in $(seq 1 300); do
    if curl -fsS http://127.0.0.1:3000/ready >/dev/null; then
        break
    fi
    if ! kill -0 "$OPEN_WEBUI_PID" 2>/dev/null; then
        echo "Open WebUI exited before readiness; see $LOG_DIR/open-webui.log" >&2
        exit 1
    fi
    if [ "$attempt" -eq 300 ]; then
        echo "Open WebUI readiness timed out; see $LOG_DIR/open-webui.log" >&2
        exit 1
    fi
    sleep 1
done

exec /start.sh
