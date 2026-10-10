#!/usr/bin/env bash
# Formats-check, type-checks and tests the project. Run from catch-a-comet/.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f globalTypes.d.luau ]; then
	echo "Downloading Roblox type definitions for luau-lsp…"
	curl -sSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== StyLua"
stylua --check src tests

echo "== luau-lsp"
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions:@roblox=globalTypes.d.luau --sourcemap=sourcemap.json src

echo "== Tests"
lune run tests/run.luau

echo "== Rojo build"
rojo build default.project.json -o catch-a-comet.rbxl
echo "All checks passed."
