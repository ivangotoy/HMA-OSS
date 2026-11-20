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
COMMON=app/src/main/java/icu/nullptr/hidemyapplist/ui/util/Common.kt
COMMON_TEXT="val isTestBuild get() = BuildConfig.VERSION_NAME.let { name ->
    name.count { it == '-' } != 1 ||
    name.count { it == '+' } > 0 ||
    name.split('-').last().length == 8
}"

# fake workspace for module-ci.conf build(): gradlew stub records what the build sees
make_work() {
    W="$SCRATCH/$1"
    mkdir -p "$W/home" "$W/out" "$W/$(dirname "$CONSTS")"
    printf 'object AppConstants {\n%s\n}\n' "$UPSTREAM_LINE" > "$W/$CONSTS"
    mkdir -p "$W/$(dirname "$COMMON")"; printf '%s\n' "$COMMON_TEXT" > "$W/$COMMON"
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
    # fixed system PATH, like the CI image: an inherited PATH can resolve python3 to a per-user
    # version-manager shim that fails under env -i with the fake HOME
    (cd "$W" && env -i PATH=/usr/local/bin:/usr/bin:/bin HOME="$W/home" OUT="$W/out" STUB_LOG="$W/gradle.log" \
        STUB_FAIL_APP="${STUB_FAIL_APP:-}" JAVA_HOME_21=/made-up/jdk \
        SIGN_KEYSTORE_B64="$(printf 'made-up keystore bytes' | base64)" SIGN_KEY_ALIAS="${T_ALIAS:-alias1}" \
        SIGN_STORE_PASSWORD="${T_STOREPW:-storepw1}" SIGN_KEY_PASSWORD="${T_KEYPW:-keypw1}" \
        SERVER_URL="${T_SERVER:-https://forge.example.invalid}" REPOSITORY="${T_REPO:-owner/HMA-OSS}" \
        bash -c 'set -euo pipefail; git() { printf "%s\\n" "$*" >> "$STUB_LOG.git"; }; . "$1"; build' _ "$CONF") > "$W/build.out" 2>&1
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

# U8: a release build is never classed as a test build, whatever the abbreviated hash length
check "build: isTestBuild length clause replaced" grep -qx '    false' "$W/$COMMON"
check "build: no 8-character clause left" sh -c '! grep -qF "last().length == 8" "$1"' _ "$W/$COMMON"
check "build: rest of isTestBuild unchanged" sh -c 'grep -qxF "    name.count { it == '"'"'+'"'"' } > 0 ||" "$1"' _ "$W/$COMMON"
check "build: both edited files assume-unchanged" sh -c 'grep -qx "update-index --assume-unchanged $2" "$1" &&
    grep -qx "update-index --assume-unchanged $3" "$1"' _ "$W/gradle.log.git" "$CONSTS" "$COMMON"
make_work moved; printf 'val isTestBuild get() = false\n' > "$W/$COMMON"; run_build; rc=$?
check "isTestBuild text moved: build refused" [ "$rc" != 0 ]
check "isTestBuild text moved: no secrets written" [ ! -e "$W/home/key.jks" ]

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

# N1: the workflow's build step runs the dispatched commit's module-ci.sh, even when main has moved on
# since the dispatch. Its run block is taken from the workflow under test and run against a local fixture
# "forge" whose main has a newer commit with a different module-ci.sh.
if command -v git >/dev/null 2>&1; then
    F="$SCRATCH/forge"; mkdir -p "$F/job"
    BLOCK="$(python3 -I -c '
import sys
out, step, ind = [], False, None
for line in open(sys.argv[1]).read().splitlines():
    s = line.strip()
    if s.startswith("- name: Build"):
        step = True
    elif step and ind is None and s == "run: |":
        ind = -1
    elif ind is not None:
        if s and ind == -1:
            ind = len(line) - len(line.lstrip())
        if s and len(line) - len(line.lstrip()) < ind:
            break
        out.append(line[ind:] if s else "")
print("\n".join(out))' "$ROOT/.forgejo/workflows/module-release.yml")"
    check "workflow build step: run block found" grep -q 'module-ci.sh build src' <<< "$BLOCK"
    (   export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
        g() { git -C "$F/seed" -c user.name=t -c user.email=t@example.invalid "$@"; }
        mkdir -p "$F/seed/.forgejo" && git init -q "$F/seed" && g symbolic-ref HEAD refs/heads/main &&
        printf '%s\n' 'printf "one %s\n" "$(git -C "$2" rev-parse HEAD)" > "$MARK"' > "$F/seed/.forgejo/module-ci.sh" &&
        g add -A && g commit -qm one && g rev-parse HEAD > "$F/base" &&
        printf '%s\n' 'printf "two\n" > "$MARK"' > "$F/seed/.forgejo/module-ci.sh" &&
        g commit -qam two && mkdir -p "$F/srv/owner" && git clone -q --bare "$F/seed" "$F/srv/owner/fixture.git" &&
        cd "$F/job" && SERVER_URL="$F/srv" REPOSITORY=owner/fixture BASE_SHA="$(cat "$F/base")" MARK="$F/mark" \
            bash -e -o pipefail -c "$BLOCK" ) > "$F/out" 2>&1
    rc=$?
    check "workflow build step: exit 0" [ "$rc" = 0 ]
    [ "$rc" = 0 ] || sed 's/^/workflow.out: /' "$F/out"
    check "workflow build step: runs the dispatched commit's module-ci.sh on its tree" \
        grep -qxF "one $(cat "$F/base" 2>/dev/null)" "$F/mark"
else
    echo "SKIP workflow build step: no git"
fi

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
# action.sh uses "&>", which the device shells (mksh, busybox ash) read as a redirect; dash reads it
# as "&" plus ">", so run it with bash, not with whatever sh is
action() { : > "$M/log"; PATH="$M/bin:$PATH" STUB_LOG="$M/log" bash "$M/action.sh" > "$M/out" 2>&1; }
STUB_INSTALL_RC=1 action; rc=$?
check "action: failed install: non-zero exit" [ "$rc" != 0 ]
check "action: failed install: no launch" sh -c '! grep -q "^am start" "$1"' _ "$M/log"
STUB_INSTALL_RC=0 action; rc=$?
check "action: install ok: exit 0" [ "$rc" = 0 ]
check "action: install ok: launched for user 0" grep -q '^am start .*--user 0' "$M/log"
STUB_PRESENT=1 action; rc=$?
check "action: already installed: exit 0" [ "$rc" = 0 ]
check "action: already installed: launched, no install" sh -c '! grep -q "^pm install" "$1" && grep -q "^am start" "$1"' _ "$M/log"

# M1: module-ci.sh build mode hands the signing secrets to the build user as environment, never as
# argv. Build mode chowns the tree, drops to uid 1000 and then runs `kill -9 -1` as uid 1000, so this
# runs only when asked for (MODULE_CI_BUILD_TEST=1), as root, inside a container.
if [ -n "${MODULE_CI_BUILD_TEST:-}" ] && [ "$(id -u)" = 0 ] && [ -f /.dockerenv ]; then
    B="$SCRATCH/bm"; mkdir -p "$B/shim" "$B/work/.forgejo"
    chmod 755 "$SCRATCH" "$B"   # uid 1000 must reach the work tree (mktemp -d is 0700)
    : > "$B/argv.log"; chmod 666 "$B/argv.log"
    # python shims: record argv, then exec the real tool with the environment untouched (a sh shim
    # would drop non-identifier entries and add PWD, hiding what module-ci.sh passes on)
    for t in env setpriv; do
        real="$(command -v "$t")"
        printf '#!%s\nimport os, sys\nopen("%s", "a").write(" ".join(["%s"] + sys.argv[1:]) + "\\n")\nos.execv("%s", ["%s"] + sys.argv[1:])\n' \
            "$(command -v python3)" "$B/argv.log" "$t" "$real" "$real" > "$B/shim/$t"
        chmod 755 "$B/shim/$t"
    done
    cp "$ROOT/.forgejo/module-ci.sh" "$B/work/.forgejo/module-ci.sh"
    cat > "$B/work/.forgejo/module-ci.conf" <<'EOF'
ZIP_PREFIX=fixture
build() {
    tr '\0' '\n' < "/proc/$$/environ" | LC_ALL=C sort > "$OUT/build-user.env"
    echo zip > "$OUT/module.zip"
}
EOF
    git -C "$B/work" init -q && git -C "$B/work" add -A &&
        git -C "$B/work" -c user.name=t -c user.email=t@example.invalid commit -qm fixture
    sha="$(git -C "$B/work" rev-parse HEAD)"
    cp -a "$B/work" "$B/work2"; cp -a "$B/work" "$B/work3"
    S1=made-up-keystore-b64 S2=made-up-alias S3='made-up store pw' S4=made-up-key-pw
    (cd "$B" && /usr/bin/env -i PATH="$B/shim:/usr/local/bin:/usr/bin:/bin" 'A-B=not-an-identifier' UNRELATED=x JAVA_HOME_21=/made-up/jdk21 \
        SERVER_URL=https://forge.example.invalid REPOSITORY=owner/fixture BASE_SHA="$sha" \
        SIGN_KEYSTORE_B64="$S1" SIGN_KEY_ALIAS="$S2" SIGN_STORE_PASSWORD="$S3" SIGN_KEY_PASSWORD="$S4" \
        bash -c 'f() { :; }; export -f f; exec bash "$1/work/.forgejo/module-ci.sh" build "$1/work"' _ "$B") \
        > "$B/build.out" 2>&1
    rc=$?
    check "build mode: exit 0" [ "$rc" = 0 ]
    [ "$rc" = 0 ] || sed 's/^/build.out: /' "$B/build.out"
    check "build mode: build-user started through setpriv" grep -q '^setpriv .* build-user ' "$B/argv.log"
    for s in "$S1" "$S2" "$S3" "$S4"; do
        check "build mode: secret '$s' in no env/setpriv argv" sh -c '! grep -qF -- "$1" "$2"' _ "$s" "$B/argv.log"
    done
    E="$B/work/.ci-out/build-user.env"
    check "build mode: build-user got the secrets as environment" \
        grep -qxF "SIGN_STORE_PASSWORD=$S3" "$E"
    check "build mode: build-user got SERVER_URL REPOSITORY BASE_SHA" sh -c 'grep -qx "SERVER_URL=https://forge.example.invalid" "$1" &&
        grep -qx "REPOSITORY=owner/fixture" "$1" && grep -qx "BASE_SHA=$2" "$1"' _ "$E" "$sha"
    check "build mode: no other variable, invalid name or function leaks" \
        sh -c '[ -s "$1" ] && ! grep -qE "^(UNRELATED|A-B|BASH_FUNC_)" "$1"' _ "$E"
    check "build mode: default git transfer limits reach build-user" \
        sh -c 'grep -qx GIT_HTTP_LOW_SPEED_LIMIT=1024 "$1" && grep -qx GIT_HTTP_LOW_SPEED_TIME=60 "$1"' _ "$E"
    sed "s|$B|<B>|g; s|$sha|<SHA>|g; s|^|ARGV |" "$B/argv.log"
    sed "s|$B|<B>|g; s|$sha|<SHA>|g; s|^|BUILD-USER-ENV |" "$E"

    # the caller may export names the script uses itself (WORK, OUT, BUILD_UID), a readonly variable
    # (bash imports SHELLOPTS from the environment as readonly) and its own git transfer limits
    SO=braceexpand:hashall:interactive-comments
    check "build mode, caller exports: SHELLOPTS arrives readonly and exported" \
        sh -c 'env -i SHELLOPTS="$1" bash -c "declare -p SHELLOPTS" | grep -q "^declare -rx SHELLOPTS="' _ "$SO"
    : > "$B/argv.log"
    (cd "$B" && /usr/bin/env -i PATH="$B/shim:/usr/local/bin:/usr/bin:/bin" JAVA_HOME_21=/made-up/jdk21 \
        SERVER_URL=https://forge.example.invalid REPOSITORY=owner/fixture BASE_SHA="$sha" \
        SIGN_KEYSTORE_B64="$S1" SIGN_KEY_ALIAS="$S2" SIGN_STORE_PASSWORD="$S3" SIGN_KEY_PASSWORD="$S4" \
        WORK=/made-up/work OUT=/made-up/out BUILD_UID=4242 SHELLOPTS="$SO" \
        GIT_HTTP_LOW_SPEED_LIMIT=2048 GIT_HTTP_LOW_SPEED_TIME=90 \
        bash "$B/work2/.forgejo/module-ci.sh" build "$B/work2") > "$B/build2.out" 2>&1
    rc=$?
    check "build mode, caller exports: exit 0" [ "$rc" = 0 ]
    [ "$rc" = 0 ] || sed 's/^/build2.out: /' "$B/build2.out"
    E="$B/work2/.ci-out/build-user.env"
    check "build mode, caller exports: build-user still uid 1000" grep -q '^setpriv --reuid=1000 .* build-user ' "$B/argv.log"
    check "build mode, caller exports: caller's git transfer limits reach build-user" \
        sh -c 'grep -qx GIT_HTTP_LOW_SPEED_LIMIT=2048 "$1" && grep -qx GIT_HTTP_LOW_SPEED_TIME=90 "$1"' _ "$E"
    check "build mode, caller exports: OUT is the script's; WORK, BUILD_UID, SHELLOPTS not passed on" \
        sh -c 'grep -qx "OUT=$2/.ci-out" "$1" && ! grep -qE "^(WORK|BUILD_UID|SHELLOPTS)=" "$1"' _ "$E" "$B/work2"

    # the root half reads the config of BASE_SHA, not of the commit the caller left checked out: the
    # checked-out tip names an upstream that does not exist, BASE_SHA names none
    printf "UPSTREAM_URL=/made-up/upstream.git\nUPSTREAM_BRANCH=main\n" >> "$B/work3/.forgejo/module-ci.conf"
    git -C "$B/work3" -c user.name=t -c user.email=t@example.invalid commit -qam tip
    : > "$B/argv.log"
    (cd "$B" && /usr/bin/env -i PATH="$B/shim:/usr/local/bin:/usr/bin:/bin" JAVA_HOME_21=/made-up/jdk21 \
        SERVER_URL=https://forge.example.invalid REPOSITORY=owner/fixture BASE_SHA="$sha" \
        SIGN_KEYSTORE_B64="$S1" SIGN_KEY_ALIAS="$S2" SIGN_STORE_PASSWORD="$S3" SIGN_KEY_PASSWORD="$S4" \
        bash "$B/work3/.forgejo/module-ci.sh" build "$B/work3") > "$B/build3.out" 2>&1
    rc=$?
    check "build mode, tip ahead of BASE_SHA: exit 0" [ "$rc" = 0 ]
    [ "$rc" = 0 ] || sed "s/^/build3.out: /" "$B/build3.out"
    check "build mode, tip ahead of BASE_SHA: BASE_SHA config used (no upstream merge)" \
        sh -c "! grep -q \"merging \" \"\$1\" && [ \"\$(head -n1 \"\$2\")\" = \"\$3\" ]" _ "$B/build3.out" "$B/work3/.ci-out/src" "$sha"
else
    echo "SKIP module-ci.sh build mode: needs MODULE_CI_BUILD_TEST=1, root and a container"
fi

# F32: module-ci.sh release cleanup deletes only a release the forge still reports as a draft. The
# publish PATCH may be applied by the forge while its reply is lost; deleting on "PUBLISHED != 1" alone
# then removes a published release. Real: log/die/jget/api/cleanup and the publish statements
# (REQ= .. PUBLISHED=1) cut from module-ci.sh; stubbed: curl (fake forge at https://forge.invalid).
if command -v python3 >/dev/null 2>&1; then
    RC="$SCRATCH/relclean"; mkdir -p "$RC/bin"; ci="$ROOT/.forgejo/module-ci.sh"
    {
        echo 'set -euo pipefail'
        echo 'API=https://forge.invalid/api/v1/repos/example/mod RELEASE_ID=7 PUBLISHED=0 SRC_SHA=0123456789abcdef0123456789abcdef01234567'
        echo 'AUTH_DIR=$(mktemp -d) AUTH_H=$AUTH_DIR/header; : > "$AUTH_H"'
        sed -n '/^log() {/p; /^die() {/p; /^jget() {/,/^print(d)/p; /^api() {/,/^}/p; /^cleanup() {/,/^}/p' "$ci"
        echo 'trap cleanup EXIT'
        echo 'if [ "$1" = publish ]; then'
        sed -n '/^REQ="\$(python3 -I -c .import json,sys;print(json.dumps({"draft":False/,/^PUBLISHED=1$/p' "$ci"
        echo 'else die "upload failed"; fi'
    } > "$RC/rel.sh"
    # fake curl: logs "METHOD URL"; PATCH exits $PATCH_RC; GET of the release answers draft=$DRAFT or fails (DRAFT=fail)
    cat > "$RC/bin/curl" <<EOF
#!/bin/sh
m=GET; p=; for a in "\$@"; do [ "\$p" = -X ] && m=\$a; p=\$a; u=\$a; done
echo "\$m \$u" >> "$RC/calls"
case "\$m" in
  PATCH) exit "\${PATCH_RC:-0}" ;;
  GET) [ "\$DRAFT" = fail ] && exit 22; printf '{"id": 7, "draft": %s}' "\$DRAFT" ;;
esac
EOF
    chmod 755 "$RC/bin/curl"
    rel() { local mode="$1"; shift; : > "$RC/calls"; env PATH="$RC/bin:$PATH" TMPDIR="$RC" "$@" bash "$RC/rel.sh" "$mode" > "$RC/err" 2>&1; }
    check "release cleanup: cleanup(), api() and the publish statements found in module-ci.sh" \
        sh -c 'grep -q "^PUBLISHED=1$" "$1" && grep -q "^cleanup() {" "$1" && grep -q "^api() {" "$1"' _ "$RC/rel.sh"
    rel publish PATCH_RC=28 DRAFT=false; rc=$?
    check "release cleanup: failed PATCH, forge reports published: job fails" [ "$rc" != 0 ]
    check "release cleanup: failed PATCH, forge reports published: PATCH sent, no DELETE" \
        sh -c 'grep -q "^PATCH " "$1" && ! grep -q "^DELETE " "$1"' _ "$RC/calls"
    grep -q '^DELETE ' "$RC/calls" && sed 's/^/calls: /' "$RC/calls"
    rel upload DRAFT=true; rc=$?
    check "release cleanup: failure before publish: job fails" [ "$rc" != 0 ]
    check "release cleanup: failure before publish deletes the draft" \
        grep -qx 'DELETE https://forge.invalid/api/v1/repos/example/mod/releases/7' "$RC/calls"
    rel publish PATCH_RC=28 DRAFT=fail; rc=$?
    check "release cleanup: failed PATCH, unreadable state: job fails" [ "$rc" != 0 ]
    check "release cleanup: failed PATCH, unreadable state: no DELETE" sh -c '! grep -q "^DELETE " "$1"' _ "$RC/calls"
    check "release cleanup: failed PATCH, unreadable state: release id logged" grep -q 'release 7' "$RC/err"
    rel publish DRAFT=false; rc=$?
    check "release cleanup: good publish: exit 0" [ "$rc" = 0 ]
    check "release cleanup: good publish: no DELETE" sh -c '! grep -q "^DELETE " "$1"' _ "$RC/calls"
else
    echo "SKIP release cleanup: no python3"
fi

# build step (module-ci.sh build): whatever the build user started is killed after the build,
# failed or not. setpriv and chown are stubs: the stub records a kill and never runs it (here the
# test user may well be the build uid, and `kill -9 -1` would end this session).
if ! command -v bash >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "SKIP module-ci.sh build step: no bash or git"
else
    BW="$(mktemp -d "$SCRATCH/case.XXXXXX")"; mkdir -p "$BW/bin"
    cat > "$BW/bin/setpriv" <<'EOF'
#!/bin/sh
case " $* " in *" kill "*) echo "kill-requested $*" >> "$SETPRIV_LOG"; exit 0 ;; esac
while [ $# -gt 0 ]; do case "$1" in --*) shift ;; *) break ;; esac; done
exec "$@"
EOF
    printf '#!/bin/sh\nexit 0\n' > "$BW/bin/chown"
    chmod 755 "$BW/bin/setpriv" "$BW/bin/chown"
    # build_step <ok|failed>: a work tree with this module-ci.sh and a conf whose build() passes or fails
    build_step() {
        _b="$BW/$1"; mkdir -p "$_b/.forgejo"
        cp "$ROOT/.forgejo/module-ci.sh" "$_b/.forgejo/"
        if [ "$1" = ok ]; then
            printf 'build() { echo zip > "$OUT/module.zip"; }\n' > "$_b/.forgejo/module-ci.conf"
        else
            printf 'build() { echo "stub build failed" >&2; return 1; }\n' > "$_b/.forgejo/module-ci.conf"
        fi
        (cd "$_b" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm t) > /dev/null 2>&1
        : > "$_b/setpriv.log"
        if [ "$(PATH="$BW/bin:$PATH" command -v setpriv)" != "$BW/bin/setpriv" ]; then
            no "build step $1: setpriv stub not first on PATH, not run"; return
        fi
        _rc=0
        (cd "$_b" && env PATH="$BW/bin:$PATH" SETPRIV_LOG="$_b/setpriv.log" SERVER_URL=https://forge.invalid \
            REPOSITORY=owner/repo BASE_SHA="$(git rev-parse HEAD)" bash .forgejo/module-ci.sh build "$_b") > "$_b/out.log" 2>&1 || _rc=$?
        if [ "$1" = ok ]; then _want=0; [ -f "$_b/.ci-out/module.zip" ] && _res=zip || _res=missing
        else _want=1; grep -q "stub build failed" "$_b/out.log" && _res=stub-failure || _res=missing; fi
        if [ "$([ "$_rc" = 0 ] && echo 0 || echo 1)" = "$_want" ] && [ "$_res" != missing ] \
            && ! grep -q "unbound variable" "$_b/out.log" && grep -q 'kill-requested .*--reuid=1000 .*kill -9 -1' "$_b/setpriv.log"; then
            ok "module-ci.sh build step $1: exit as expected, build user's processes killed"
        else
            no "module-ci.sh build step $1 (rc=$_rc, $_res, kills: $(grep -c kill-requested "$_b/setpriv.log")): $(tail -n 2 "$_b/out.log" | tr '\n' ' ')"
        fi
    }
    build_step ok
    build_step failed
fi

echo "passed $PASS failed $FAIL"
[ "$FAIL" = 0 ]
