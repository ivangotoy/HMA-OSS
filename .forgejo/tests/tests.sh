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

# H2: local.properties is read by java.util.Properties; plain secrets give the same bytes as before
check "plain secrets: local.properties bytes unchanged" cmp -s "$SCRATCH/ok/gradle.log.props" \
    <(printf 'storePassword=%s\nkeyAlias=%s\nkeyPassword=%s\nfileDir=%s\n' storepw1 alias1 keypw1 "$SCRATCH/ok/home/key.jks")
make_work esc
T_STOREPW='a\tb\c' T_ALIAS='al ias' T_KEYPW="$(printf 'p\303\244#=:x\tq\360\237\230\200')" run_build; rc=$?
check "special secrets: build exit 0" [ "$rc" = 0 ]
check "special secrets: escaped for Properties" cmp -s "$W/gradle.log.props" <(printf '%s\n' \
    'storePassword=a\\tb\\c' 'keyAlias=al ias' 'keyPassword=p\u00e4#=:x\tq\ud83d\ude00' "fileDir=$W/home/key.jks")
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
if command -v "$JAVA" >/dev/null 2>&1; then
    cat > "$SCRATCH/P.java" <<'EOF'
public class P { public static void main(String[] a) throws Exception {
    java.util.Properties p = new java.util.Properties();
    try (java.io.InputStream in = new java.io.FileInputStream(a[0])) { p.load(in); }
    for (String k : new String[] {"storePassword", "keyAlias", "keyPassword"}) {
        StringBuilder b = new StringBuilder(k + "=");
        for (char c : p.getProperty(k).toCharArray()) b.append(String.format("%04x ", (int) c));
        System.out.println(b.toString().trim());
    } } }
EOF
    want="$(T_STOREPW='a\tb\c' T_ALIAS='al ias' T_KEYPW="$(printf 'p\303\244#=:x\tq\360\237\230\200')" python3 -I -c '
import os
for k, v in (("storePassword", "T_STOREPW"), ("keyAlias", "T_ALIAS"), ("keyPassword", "T_KEYPW")):
    u = os.environ[v].encode("utf-16-be")
    print(k + "=" + " ".join(u[i:i + 2].hex() for i in range(0, len(u), 2)))')"
    got="$("$JAVA" "$SCRATCH/P.java" "$W/gradle.log.props" 2>/dev/null)"
    check "special secrets: Properties.load reads them back unchanged" [ "$got" = "$want" ]
else
    echo "SKIP Properties.load round trip: no java"
fi

# edge blanks and trailing line breaks are dropped, as the plain printf format did (Properties.load
# skips leading blanks; a final line break only ended the line)
make_work edge
T_STOREPW="$(printf 'storepw1\nX')" T_STOREPW="${T_STOREPW%X}" T_ALIAS="$(printf ' \talias1')" T_KEYPW="$(printf 'keypw1\r\nX')" \
    T_KEYPW="${T_KEYPW%X}" run_build; rc=$?
check "edge blanks: build exit 0" [ "$rc" = 0 ]
check "edge blanks: same values as plain secrets" cmp -s "$W/gradle.log.props" \
    <(printf 'storePassword=%s\nkeyAlias=%s\nkeyPassword=%s\nfileDir=%s\n' storepw1 alias1 keypw1 "$W/home/key.jks")

# H3: the feed URL must be a plain https URL before it reaches sed and the Kotlin source
make_work port; T_SERVER=https://forge.example.invalid:3000/sub run_build; rc=$?
check "server URL with port and path: accepted" [ "$rc" = 0 ]
check "server URL with port and path: feed URL" \
    grep -qF '"https://forge.example.invalid:3000/sub/owner/HMA-OSS/raw/branch/main/.forgejo/app-update.json"' "$W/$CONSTS"
n=0
for bad in 'S=http://forge.example.invalid' 'S=https://forge.example.invalid/a|b' 'S=https://forge.example.invalid/a&b' \
           'S=https://forge.example.invalid/"x' 'S=https://forge.example.invalid/$x' 'S=https://forge.example.invalid/' \
           'R=owner/HMA-OSS"' 'R=owner/a/b' 'R=owner'; do
    n=$((n + 1)); make_work "bad$n"
    if [ "${bad%%=*}" = S ]; then T_SERVER="${bad#S=}" run_build; else T_REPO="${bad#R=}" run_build; fi; rc=$?
    check "refused: ${bad#?=}" [ "$rc" != 0 ]
    check "refused: ${bad#?=}: AppConstants unchanged" grep -qxF "$UPSTREAM_LINE" "$W/$CONSTS"
    check "refused: ${bad#?=}: no secrets written" [ ! -e "$W/home/key.jks" ]
done

# H4: release_files writes the in-app update feed as complete JSON with a final newline
W="$SCRATCH/feed"; mkdir -p "$W/.forgejo"
(cd "$W" && BUILT_VERSION=main-0123abc VERSION=main-0123abc-ci7 BODY="$(printf 'line one\nsha256 "x"')" \
    ZIP_URL=https://forge.example.invalid/owner/HMA-OSS/releases/download/vmain-0123abc-ci7/m.zip \
    bash -c 'set -euo pipefail; . "$1"; release_files; [ "$RELEASE_FILES" = .forgejo/app-update.json ]' _ "$CONF") > "$W/out" 2>&1
check "release_files: exit 0" [ $? = 0 ]
check "release_files: feed content" cmp -s "$W/.forgejo/app-update.json" <(printf '%s\n' '{' \
    '  "tag_name": "main-0123abc",' '  "name": "HMA-OSS main-0123abc-ci7",' '  "body": "line one\nsha256 \"x\"",' \
    '  "html_url": "https://forge.example.invalid/owner/HMA-OSS/releases/download/vmain-0123abc-ci7/m.zip"' '}')

# module scripts (run by the root manager's sh): stubs for pm, am and ui_print
ASSETS="$ROOT/zygote/src/main/assets"

# U4: a failed fresh install names user 0
out="$(sh -c 'ui_print() { echo "$*"; }
pm() { case "$1" in install) return 1 ;; esac; return 0; }
MODPATH=/made/up; . "$1"' _ "$ASSETS/customize.d/35-install-manager-app.sh" 2>&1)"
check "35-install: failed fresh install names user 0" grep -qxF '! Cannot install the manager app for user 0' <<< "$out"

# U5: action.sh launches the manager only when it is installed
M="$SCRATCH/mod"; mkdir -p "$M/bin"
cp "$ASSETS/action.sh" "$M/action.sh"; printf ':\n' > "$M/update_desc.sh"
cat > "$M/bin/pm" <<'EOF'
#!/bin/sh
case "$1" in
    list) printf 'Users:\n\tUserInfo{0:Owner:c13} running\n' ;;
    path) [ -n "${STUB_PRESENT:-}" ] || exit 1; echo package:/data/app/made-up/base.apk ;;
    install) echo "pm install $*" >> "$STUB_LOG"; exit "${STUB_INSTALL_RC:-0}" ;;
esac
EOF
printf '#!/bin/sh\necho "am $*" >> "$STUB_LOG"\n' > "$M/bin/am"
chmod +x "$M/bin/pm" "$M/bin/am"
action() { : > "$M/log"; PATH="$M/bin:$PATH" STUB_LOG="$M/log" sh "$M/action.sh" > "$M/out" 2>&1; }
STUB_INSTALL_RC=1 action; rc=$?
check "action: failed install: non-zero exit" [ "$rc" != 0 ]
check "action: failed install: no launch" sh -c '! grep -q "^am start" "$1"' _ "$M/log"
STUB_INSTALL_RC=0 action; rc=$?
check "action: install ok: exit 0" [ "$rc" = 0 ]
check "action: install ok: launched for user 0" grep -q '^am start .*--user 0' "$M/log"
STUB_PRESENT=1 action; rc=$?
check "action: already installed: exit 0" [ "$rc" = 0 ]
check "action: already installed: launched, no install" sh -c '! grep -q "^pm install" "$1" && grep -q "^am start" "$1"' _ "$M/log"

echo "passed $PASS failed $FAIL"
[ "$FAIL" = 0 ]
