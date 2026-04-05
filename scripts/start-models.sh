#!/bin/bash
# Start MLX-LM servers for Mixtape
# Usage:
#   ./scripts/start-models.sh           # start both models
#   ./scripts/start-models.sh coder     # start coder only
#   ./scripts/start-models.sh architect # start architect only

MODELS_DIR="$HOME/models"

start_coder() {
  echo "Starting coder (Qwen2.5-Coder-32B-Q8) on port 8080..."
  (cd "$MODELS_DIR" && uv run mlx_lm.server \
    --model "$MODELS_DIR/qwen2.5-coder-32b-q8" \
    --port 8080 \
    --host 127.0.0.1) &
  echo "  PID: $!"
}

start_architect() {
  echo "Starting architect (Qwen2.5-72B-Q6) on port 8081..."
  (cd "$MODELS_DIR" && uv run mlx_lm.server \
    --model "$MODELS_DIR/qwen2.5-72b-q6" \
    --port 8081 \
    --host 127.0.0.1) &
  echo "  PID: $!"
}

case "${1:-both}" in
  coder)
    start_coder
    ;;
  architect)
    start_architect
    ;;
  both)
    start_coder
    start_architect
    ;;
  *)
    echo "Usage: $0 [coder|architect|both]"
    exit 1
    ;;
esac

echo ""
echo "Models starting in background. Use 'kill %1 %2' or Ctrl+C to stop."
echo "Check Mixtape health: curl http://localhost:4000/health"
wait
