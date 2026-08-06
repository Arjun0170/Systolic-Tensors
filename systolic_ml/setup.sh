#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "Error: $PYTHON_BIN is not installed." >&2
    echo "On Ubuntu/WSL, install it with:" >&2
    echo "  sudo apt update && sudo apt install -y python3 python3-venv python3-pip" >&2
    exit 1
fi

echo "Using $($PYTHON_BIN --version)"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "Creating virtual environment in $VENV_DIR ..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

echo "Upgrading pip ..."
"$VENV_DIR/bin/python" -m pip install \
    --retries 20 --resume-retries 20 --timeout 120 \
    --upgrade pip

echo "Installing project dependencies ..."
"$VENV_DIR/bin/python" -m pip install \
    --retries 20 --resume-retries 20 --timeout 120 \
    -r requirements.txt

echo "Checking imports ..."
"$VENV_DIR/bin/python" - <<'PY'
import numpy
import torch

print(f"NumPy {numpy.__version__}")
print(f"PyTorch {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"CUDA device: {torch.cuda.get_device_name(0)}")
PY

echo
echo "Setup complete. Run:"
echo "  ./run_project.sh infer"
echo "  ./run_project.sh array"
echo "  ./run_project.sh train"
echo "  ./run_project.sh all"
