#!/bin/sh
# Fails if this addon's copy of KennyShared differs from the canonical one.
# Usage: tools/check_lib.sh <wow-forever-addons checkout>
set -e
cd "$(dirname "$0")/.."
CANON="$1/lib/KennyShared"
status=0
for f in Compat.lua Core.lua Hub.lua VERSION; do cmp -s "$CANON/$f" "Libs/KennyShared/$f" || { echo "DRIFT: Libs/KennyShared/$f"; status=1; }; done
for f in tests/run.sh tests/test_blizzard_docs.lua tests/test_selfcheck.lua tests/test_hub.lua tools/verify_api.py tools/host_api.py tools/check_lib.sh tools/gen_locale.py tools/verify_hosts.py; do
  cmp -s "$CANON/$f" "$f" || { echo "DRIFT: $f"; status=1; }
done
[ $status -eq 0 ] && echo "KennyShared $(cat Libs/KennyShared/VERSION) in sync"
exit $status
