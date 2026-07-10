#!/usr/bin/env bash
# chickho test gate: import, sim suite, end-to-end flow suite.
# This is what CI will run per platform once the M2 matrix lands.
set -euo pipefail
GODOT="${GODOT:-$HOME/Godot/Godot_v4.7-stable_linux.x86_64}"
cd "$(dirname "$0")"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd
"$GODOT" --headless --path . -s res://tests/run_flow.gd
"$GODOT" --headless --path . -s res://tests/fuzz.gd -- --runs "${FUZZ:-10}"
