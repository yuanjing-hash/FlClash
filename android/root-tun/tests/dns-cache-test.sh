#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=${FLCLASH_TEST_RUNTIME:-$TESTS/../../app/src/main/assets/root-tun/runtime.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flclash-dns-cache.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
R=$WORK/runtime
mkdir -p "$R/config" "$R/logs"
sed -n '/^flush_dns_cache() {/,/^update_private_dns() {/p' "$SOURCE" | sed '$d' > "$WORK/functions.sh"
. "$WORK/functions.sh"
root_proxy() { printf '%s\n' "$1" >> "$WORK/calls"; return "${PROXY_RESULT:-0}"; }
runtime_log() { printf '%s\n' "$*" >> "$WORK/warnings"; }
flush_dns_cache
[ ! -f "$WORK/calls" ]
printf '0\n' > "$R/config/per-app-dns"
flush_dns_cache
[ ! -f "$WORK/calls" ]
printf '1\n' > "$R/config/per-app-dns"
flush_dns_cache
[ "$(cat "$WORK/calls")" = flush-dns ]
PROXY_RESULT=1
flush_dns_cache
grep -q 'system DNS cache flush incomplete' "$WORK/warnings"
runtime_log() { return 1; }
flush_dns_cache || exit 1
echo 'PASS per-app DNS refreshes system caches without blocking startup on unsupported ROMs'

sed -n '/^launch_core() {/,/^core_healthy() {/p' "$SOURCE" | sed '$d' > "$WORK/launch.sh"
. "$WORK/launch.sh"
RUN=$R/run STATE=$R/state BOOT=test-boot CORE=true
mkdir -p "$RUN" "$STATE"
owns() { return 0; }
ticks() { printf '1\n'; }
cat() {
    if [ "$*" = /proc/sys/kernel/random/boot_id ]; then printf '%s\n' "$BOOT"; else command cat "$@"; fi
}
flush_dns_cache() { printf '%s\n' early > "$WORK/early-flush"; }
launch_core
wait
[ ! -f "$WORK/early-flush" ]
echo 'PASS launching the Core cannot flush application caches before capture is ready'

sed -n '/^cleanup() {/,/^launch_core() {/p' "$SOURCE" | sed '$d' > "$WORK/cleanup.sh"
. "$WORK/cleanup.sh"
stop_core() { phase=stopped; }
restore_system_proxy() { return "${RESTORE_RESULT:-0}"; }
vacant() { phase=native; }
compare_restoration() { [ "$phase" = native ]; }
runtime_error() { return 0; }
ip() { [ "$*" != 'link show flcrtun0' ]; }
iptables() { return 1; }
ip6tables() { return 1; }
flush_dns_cache() { printf '%s\n' "$phase" >> "$WORK/restored-flushes"; }
printf '%s\n' "$BOOT" > "$STATE/owned.boot"
touch "$STATE/owned"
cleanup
[ "$(cat "$WORK/restored-flushes")" = native ]
rm -f "$WORK/restored-flushes"
printf '%s\n' "$BOOT" > "$STATE/owned.boot"
touch "$STATE/owned"
RESTORE_RESULT=1
if cleanup; then exit 1; fi
[ ! -f "$WORK/restored-flushes" ]
echo 'PASS stop refreshes caches only after native networking has been restored'
