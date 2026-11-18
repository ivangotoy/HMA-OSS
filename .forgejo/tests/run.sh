#!/bin/sh
# Offline stub tests for the fork's CI config and module scripts: sh .forgejo/tests/run.sh [repo-root]
# Uses made-up values only; needs bash, python3, base64. Not packaged into the module zip or the APK.
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/tests.sh" "$ROOT"
