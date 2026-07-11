#!/usr/bin/env bash
# copycats test gate: import, sim suite, solo flow, couch flow, fuzz.
# CI runs this on linux; the determinism matrix runs the dump per platform.
set -euo pipefail
GODOT="${GODOT:-$HOME/Godot/Godot_v4.7-stable_linux.x86_64}"
cd "$(dirname "$0")"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . -s res://tests/run_tests.gd
"$GODOT" --headless --path . -s res://tests/run_flow.gd
"$GODOT" --headless --path . -s res://tests/run_couch_flow.gd
"$GODOT" --headless --path . -s res://tests/fuzz.gd -- --runs "${FUZZ:-10}"
