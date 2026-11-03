#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" -e '/^export PATH=/d' \
    -e '/^safe_tree || exit 1/,$d' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/functions.sh"
# shellcheck source=/dev/null
. "$WORK/functions.sh"
printf '%s\n' '# generated at 1' ':OUTPUT ACCEPT [5:999]' \
    '-A OUTPUT -c 10 99 -m comment --comment "one" -j ACCEPT' \
    'default via fe80::1 dev wlan0 proto ra metric 1024 expires 100sec pref medium' > "$WORK/before"
printf '%s\n' '# generated at 2' ':OUTPUT ACCEPT [9:123]' \
    '-A OUTPUT -c 20 199 -m comment --comment "two" -j ACCEPT' \
    'default via fe80::1 dev wlan0 proto kernel metric 1024 expires 80sec pref medium' > "$WORK/after"
normalize "$WORK/before" > "$WORK/normalized-before"
normalize "$WORK/after" > "$WORK/normalized-after"
cmp "$WORK/normalized-before" "$WORK/normalized-after"
sed 's/fe80::1/fe80::2/' "$WORK/after" > "$WORK/changed"
normalize "$WORK/changed" > "$WORK/normalized-after"
if cmp -s "$WORK/normalized-before" "$WORK/normalized-after"; then exit 1; fi
echo 'PASS normalization removes dynamic counters/comments/expiry/protocol metadata and retains next-hop changes'
IDENTITY="$$ $(ticks "$$") $BOOT"
export IDENTITY
mkdir -p "$RUN" "$STATE" "$R/logs"
claim_owner
printf stale > "$R/logs/restore-diff.txt"
publish running
[ ! -s "$R/logs/restore-diff.txt" ]
printf stale > "$R/logs/restore-diff.txt"
vacant() { return 0; }
cleanup
[ ! -s "$R/logs/restore-diff.txt" ]
unlock owner
echo 'PASS successful start and cleanup clear restore-diff warning marker'
dd if=/dev/zero of="$R/logs/watchdog.log" bs=1048576 count=1 2>/dev/null
runtime_log watchdog 'rotation probe'
[ -f "$R/logs/watchdog.log.1" ] && [ "$(stat -c %s "$R/logs/watchdog.log")" -lt 1048576 ]
dd if=/dev/zero of="$R/logs/boot.log" bs=1048576 count=1 2>/dev/null
runtime_log boot 'rotation probe'
[ -f "$R/logs/boot.log.1" ] && [ "$(stat -c %s "$R/logs/boot.log")" -lt 1048576 ]
echo 'PASS watchdog and boot log rotation retain only current and previous log'
