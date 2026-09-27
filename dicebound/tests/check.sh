#!/usr/bin/env bash
# Static checks + logic tests. Needs rojo, luau-lsp (with Roblox globalTypes.d.luau) and luau.
#   TOOLS=/path/to/bin DEFS=/path/to/globalTypes.d.luau tests/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
TOOLS=${TOOLS:-}
DEFS=${DEFS:-globalTypes.d.luau}
bin() { if [ -n "$TOOLS" ]; then echo "$TOOLS/$1"; else echo "$1"; fi; }
"$(bin rojo)" build -o "${TMPDIR:-/tmp}/dicebound-check.rbxl"
"$(bin rojo)" sourcemap default.project.json -o sourcemap.json
"$(bin luau-lsp)" analyze --definitions="$DEFS" --sourcemap=sourcemap.json src
python3 tests/run.py "$(bin luau)"
