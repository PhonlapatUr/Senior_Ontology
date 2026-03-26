#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv311/bin/python"

cd "$ROOT_DIR"

echo "Running unit tests with verbose output..."
"$PYTHON_BIN" -m coverage erase
"$PYTHON_BIN" -m coverage run -m unittest -v \
  backend_tests/UnitTest_ScorePollutant.py \
  backend_tests/UnitTest_User_Login_Validation.py

echo
echo "Coverage summary:"
"$PYTHON_BIN" -m coverage report -m

echo
echo "Generating HTML coverage report..."
"$PYTHON_BIN" -m coverage html -d backend_tests/htmlcov
echo "HTML report: backend_tests/htmlcov/index.html"
