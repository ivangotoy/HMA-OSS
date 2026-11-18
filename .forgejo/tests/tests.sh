#!/usr/bin/env bash
# Stub tests, started by run.sh. $1 = repo root whose files are tested.
set -u
ROOT="$1"
CONF="$ROOT/.forgejo/module-ci.conf"
SCRATCH="$(mktemp -d)"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$SCRATCH"' EXIT
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else no "$name"; fi; }

UPSTREAM_LINE='    const val UPDATE_CHECK_URL = "https://api.github.com/repos/frknkrc44/HMA-OSS/releases/latest"'
CONSTS=app/src/main/java/icu/nullptr/hidemyapplist/data/AppConstants.kt

# fake workspace for module-ci.conf build(): gradlew stub records what the build sees
make_work() {
    W="$SCRATCH/$1"
    mkdir -p "$W/home" "$W/out" "$W/$(dirname "$CONSTS")"
    printf 'object AppConstants {\n%s\n}\n' "$UPSTREAM_LINE" > "$W/$CONSTS"
    cat > "$W/gradlew" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
    *:app:assemble*) [ -z "${STUB_FAIL_APP:-}" ] || exit 1 ;;
    *:zygote:assemble*)
        stat -c '%a' "$HOME/key.jks" local.properties > "$STUB_LOG.perm"
        cp local.properties "$STUB_LOG.props"
        mkdir -p zygote/build/outputs/magisk/release
        echo zip > zygote/build/outputs/magisk/release/module-release.zip ;;
esac
EOF
}

# runs build() as module-ci.sh build-user does: a bash with set -euo pipefail that exits after build
run_build() {
    (cd "$W" && env -i PATH="$PATH" HOME="$W/home" OUT="$W/out" STUB_LOG="$W/gradle.log" \
        STUB_FAIL_APP="${STUB_FAIL_APP:-}" JAVA_HOME_21=/made-up/jdk \
        SIGN_KEYSTORE_B64="$(printf 'made-up keystore bytes' | base64)" SIGN_KEY_ALIAS="${T_ALIAS:-alias1}" \
        SIGN_STORE_PASSWORD="${T_STOREPW:-storepw1}" SIGN_KEY_PASSWORD="${T_KEYPW:-keypw1}" \
        SERVER_URL="${T_SERVER:-https://forge.example.invalid}" REPOSITORY="${T_REPO:-owner/HMA-OSS}" \
        bash -c 'set -euo pipefail; git() { :; }; . "$1"; build' _ "$CONF") > "$W/build.out" 2>&1
}

# H1: secrets are owner-only while Gradle runs and gone after the build shell exits
make_work ok; run_build; rc=$?
check "build: exit 0" [ "$rc" = 0 ]
check "build: module.zip in OUT" [ -f "$W/out/module.zip" ]
check "build: key.jks and local.properties are 0600 during gradle" [ "$(tr "\n" " " 2>/dev/null < "$W/gradle.log.perm")" = "600 600 " ]
check "build: key.jks removed after success" [ ! -e "$W/home/key.jks" ]
check "build: local.properties removed after success" [ ! -e "$W/local.properties" ]
check "build: update URL points at the forge feed" \
    grep -qF '"https://forge.example.invalid/owner/HMA-OSS/raw/branch/main/.forgejo/app-update.json"' "$W/$CONSTS"

make_work fail; STUB_FAIL_APP=1 run_build; rc=$?
check "failed gradle step: build fails" [ "$rc" != 0 ]
check "failed gradle step: key.jks removed" [ ! -e "$W/home/key.jks" ]
check "failed gradle step: local.properties removed" [ ! -e "$W/local.properties" ]

echo "passed $PASS failed $FAIL"
[ "$FAIL" = 0 ]
