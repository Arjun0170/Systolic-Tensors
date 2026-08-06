#!/usr/bin/env bash
set -Eeuo pipefail
export PYTHONDONTWRITEBYTECODE=1

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PYTHON="$PROJECT_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    echo "The project environment is missing. Running setup first ..."
    "$PROJECT_DIR/setup.sh"
fi

COMMAND="${1:-infer}"
case "$COMMAND" in
    infer)
        "$PYTHON" infer_int8.py
        ;;
    array)
        "$PYTHON" run_on_array.py
        ;;
    train)
        "$PYTHON" train_mlp.py
        ;;
    all)
        "$PYTHON" train_mlp.py
        "$PYTHON" infer_int8.py
        "$PYTHON" run_on_array.py
        ;;
    help|-h|--help)
        cat <<'EOF'
Usage: ./run_project.sh [infer|array|train|all]

  infer  Run INT8 MNIST inference using the existing weights (default)
  array  Generate and verify the 16x16 RTL test-vector tiles
  train  Retrain the PyTorch MLP and replace mlp_weights.npz
  all    Train, run inference, then generate RTL test vectors
EOF
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        echo "Run ./run_project.sh --help for available commands." >&2
        exit 2
        ;;
esac
