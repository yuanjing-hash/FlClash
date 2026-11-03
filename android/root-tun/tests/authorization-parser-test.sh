#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=$TESTS/../../app/src/main/assets/root-tun/authorization.sh
TEST_TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TEST_TMP/flclash-auth-parser.XXXXXX")
case "$WORK" in "$TEST_TMP"/flclash-auth-parser.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT
R=$WORK/runtime
export TMPDIR=$WORK/tmp
mkdir -p "$R/config" "$TMPDIR" "$WORK/ksu" "$WORK/ap" "$WORK/bin"
sed -e "s|/data/adb/ksu|$WORK/ksu|g" -e "s|/data/adb/ap|$WORK/ap|g" "$SOURCE" > "$WORK/authorization.sh"
. "$WORK/authorization.sh"
check() {
    verdict=$(manager_authorization "$2" "$3" 2> "$WORK/stderr")
    if [ "$verdict" != "$1" ] || [ -s "$WORK/stderr" ]; then
        printf 'FAIL %s: expected=%s actual=%s\n' "$4" "$1" "$verdict" >&2
        cat "$WORK/stderr" >&2
        exit 1
    fi
    printf 'PASS authorization parser: %s\n' "$4"
}
for version in 3 4; do
    case "$version" in
        3) bytes=784; header='\125\123\113\177\003\000\000\000\003\000\000\000' ;;
        4) bytes=792; header='\125\123\113\177\004\000\000\000\004\000\000\000' ;;
    esac
    dd if=/dev/zero of="$WORK/ksu/.allowlist" bs="$bytes" count=1 2>/dev/null
    printf '%bcom.follow.clash.root\000' "$header" | dd of="$WORK/ksu/.allowlist" conv=notrunc 2>/dev/null
    printf '\316\047\000\000\001' | dd of="$WORK/ksu/.allowlist" bs=1 seek=268 conv=notrunc 2>/dev/null
    check granted 10190 kernelsu "KernelSU v$version granted"
    check denied 10191 kernelsu "KernelSU v$version different UID"
    printf '\000' | dd of="$WORK/ksu/.allowlist" bs=1 seek=272 conv=notrunc 2>/dev/null
    check denied 10190 kernelsu "KernelSU v$version revoked"
    printf '\002' | dd of="$WORK/ksu/.allowlist" bs=1 seek=272 conv=notrunc 2>/dev/null
    check unknown 10190 kernelsu "KernelSU v$version invalid grant"
done
printf '\011' | dd of="$WORK/ksu/.allowlist" bs=1 seek=4 conv=notrunc 2>/dev/null
check unknown 10190 kernelsu 'KernelSU unsupported version'
printf truncated > "$WORK/ksu/.allowlist"
check unknown 10190 kernelsu 'KernelSU truncated file'
cat > "$WORK/bin/magisk" <<'MAGISK'
#!/bin/sh
if [ "$(cat "$AUTH_POLICY")" = failed ]; then exit 1; fi
cat "$AUTH_POLICY"
MAGISK
chmod +x "$WORK/bin/magisk"
export AUTH_POLICY=$WORK/policy
export PATH="$WORK/bin:$PATH"
printf 'policy=2|until=0\n' > "$AUTH_POLICY"
check granted 10190 magisk 'Magisk granted'
printf 'policy=1|until=0\n' > "$AUTH_POLICY"
check denied 10190 magisk 'Magisk denied'
printf 'policy=2|until=1\n' > "$AUTH_POLICY"
check denied 10190 magisk 'Magisk expired'
printf 'malformed\n' > "$AUTH_POLICY"
check unknown 10190 magisk 'Magisk malformed response'
printf 'failed\n' > "$AUTH_POLICY"
check unknown 10190 magisk 'Magisk command failed'
printf '%s\n' 'pkg,exclude,allow,uid,to_uid,sctx' 'com.follow.clash.root,0,1,10190,0,u:r:su:s0' > "$WORK/ap/package_config"
check granted 10190 apatch 'APatch granted'
check denied 10191 apatch 'APatch different UID'
printf '%s\n' 'pkg,exclude,allow,uid,to_uid,sctx' 'com.follow.clash.root,0,0,10190,0,u:r:su:s0' > "$WORK/ap/package_config"
check denied 10190 apatch 'APatch revoked'
printf 'malformed\n' > "$WORK/ap/package_config"
check unknown 10190 apatch 'APatch malformed file'
