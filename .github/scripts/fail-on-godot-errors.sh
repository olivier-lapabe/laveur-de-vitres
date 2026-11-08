#!/usr/bin/env bash
# Fail when a Godot log contains engine or script errors.
# Godot exits with code 0 after most errors, so CI reads its output instead.
set -euo pipefail

log="$1"
# Strip ANSI colors before matching, in case Godot colors its output.
if sed -E 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^(USER |SCRIPT )?ERROR:'; then
  echo "::error::Godot reported errors in $(basename "$log") (see the lines above)"
  exit 1
fi
