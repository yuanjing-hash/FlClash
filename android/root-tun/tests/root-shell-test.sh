#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=$TESTS/../../app/src/main/assets/root-tun/runtime.sh
TEST_TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TEST_TMP/flclash-root-shell.XXXXXX")
case "$WORK" in "$TEST_TMP"/flclash-root-shell.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT
export FLCLASH_TEST_BOOTSTRAPS=$WORK/bootstrap-count
: > "$FLCLASH_TEST_BOOTSTRAPS"
cat > "$WORK/busybox" <<'BUSYBOX'
#!/bin/sh
[ "$(wc -l < "$FLCLASH_TEST_BOOTSTRAPS")" -lt 3 ] || exit 90
[ "$1" = sh ] && [ "$ASH_STANDALONE" = 1 ] || exit 91
printf 'exec\n' >> "$FLCLASH_TEST_BOOTSTRAPS"
shift
exec sh "$@"
BUSYBOX
chmod +x "$WORK/busybox"
sed -e '/^set -u/,$d' -e "s|/data/adb/ksu/bin/busybox|$WORK/busybox|g" \
    "$SOURCE" > "$WORK/runtime.sh"
cat >> "$WORK/runtime.sh" <<'PROBE'
if [ "$1" = parent ]; then
    sh "$0" child
else
    printf 'ready %s\n' "$ASH_STANDALONE"
fi
PROBE
unset FLCLASH_ROOT_BUSYBOX_PID
[ "$(sh "$WORK/runtime.sh" parent)" = 'ready 1' ]
[ "$(wc -l < "$FLCLASH_TEST_BOOTSTRAPS" | tr -d ' ')" = 2 ]
echo 'PASS runtime and child use BusyBox standalone exactly once per process'
