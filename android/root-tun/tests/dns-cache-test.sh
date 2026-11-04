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
echo 'PASS per-app DNS refreshes system caches without blocking startup on unsupported ROMs'
