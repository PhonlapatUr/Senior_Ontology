#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="$ROOT_DIR/.venv311/bin/python"

cd "$ROOT_DIR"

echo "Running unit tests with verbose output..."
"$PYTHON_BIN" -m coverage erase
"$PYTHON_BIN" -m coverage run -m unittest -v \
  unit_test/UnitTest_1_0_User_Registration.py \
  unit_test/UnitTest_2_0_Login.py \
  unit_test/UnitTest_3_0_Route_No_Pollution_Preference.py \
  unit_test/UnitTest_4_0_Route_With_Pollution_Preference.py

echo
echo "Coverage summary:"
"$PYTHON_BIN" -m coverage report -m

echo
echo "Generating HTML coverage report..."
"$PYTHON_BIN" -m coverage html -d unit_test/htmlcov
echo "HTML report: unit_test/htmlcov/index.html"
