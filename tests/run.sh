#!/bin/sh
# KennyShared 2.0.0 test runner (copied from wow-forever-addons lib/KennyShared; do not edit the copy).
# Syntax, lint, mock-client tests, then checks against Blizzard's Forever UI source when a path is given.
# Usage: tests/run.sh [path to Gethe/wow-ui-source checkout, forever branch] [folder with host addon checkouts]
# Host addons a plugin uses are listed in its TOC as ## X-Hosts: BigWigs, DeadlyBossMods (see tools/verify_hosts.py).
set -e
cd "$(dirname "$0")/.."
[ -d /workspace/lua51/bin ] && PATH=/workspace/lua51/bin:$PATH
ADDON=$(ls *.toc | head -1 | sed 's/\.toc$//')
FILES=$(grep -E '\.lua$' "$ADDON.toc" | grep -v '^#' | tr -d '\r' | tr '\\' '/')
for f in $FILES; do luac -p "$f"; done
echo "luac -p OK"
luacheck . --formatter plain
echo "luacheck OK"
python3 tools/gen_locale.py --check
for t in tests/test_*.lua; do [ "$t" = tests/test_blizzard_docs.lua ] || lua "$t"; done
lua tests/test_blizzard_docs.lua "$1" "$ADDON"
if [ -n "$1" ]; then
  python3 tools/verify_api.py "$1" $FILES > /tmp/verify_api.out || { cat /tmp/verify_api.out; exit 1; }
  tail -1 /tmp/verify_api.out
fi
HOSTS=$(grep -E '^## X-Hosts:' "$ADDON.toc" | sed 's/^## X-Hosts://; s/,/ /g' | tr -d '\r')
if [ -n "$2" ] && [ -n "$HOSTS" ]; then python3 tools/verify_hosts.py "$2" $HOSTS > /tmp/verify_hosts.out || { cat /tmp/verify_hosts.out; exit 1; }; tail -1 /tmp/verify_hosts.out; fi
