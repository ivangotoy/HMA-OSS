#!/bin/sh
# Offline stub tests for the fork's CI config and module scripts: sh .forgejo/tests/run.sh [repo-root]
# Uses made-up values only; needs bash, python3, base64. Not packaged into the module zip or the APK.
ROOT="$(cd "${1:-$(dirname "$0")/../..}" && pwd)" || exit 2
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/tests.sh" "$ROOT"
