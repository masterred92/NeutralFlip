#!/bin/sh
# Offline checks: syntax, lint, mock-client tests, and (optional) API check against Blizzard's UI source.
# Usage: tests/run.sh [path to Gethe/wow-ui-source checkout, forever branch]
set -e
cd "$(dirname "$0")/.."
[ -d /workspace/lua51/bin ] && PATH=/workspace/lua51/bin:$PATH
for f in *.lua; do luac -p "$f"; done && echo "luac -p OK"
luacheck . --formatter plain && echo "luacheck OK"
for t in tests/test_*.lua; do lua "$t"; done
if [ -n "$1" ]; then python3 tools/verify_api.py "$1" *.lua | tail -1; fi
