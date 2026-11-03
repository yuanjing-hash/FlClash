#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=${FLCLASH_TEST_RUNTIME:-$TESTS/../../app/src/main/assets/root-tun/runtime.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flclash-stop-core.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
RUN=$WORK/run
mkdir -p "$RUN"
sed -n '/^stop_core() {/,/^cleanup() {/p' "$SOURCE" | sed '$d' > "$WORK/functions.sh"
. "$WORK/functions.sh"
sleep() { :; }
alive() { recorded_pid=4242; [ "$live" = 1 ]; }
kill() {
    [ "$2" = 4242 ] || exit 99
    printf '%s\n' "$1" >> "$WORK/signals"
    case "$CASE:$1" in
        exited-before-term:-TERM) live=0; return 1 ;;
        exits-on-term:-TERM|exits-on-kill:-KILL) live=0; return 0 ;;
        denied-term:-TERM|denied-kill:-KILL) return 1 ;;
    esac
    return 0
}
for CASE in absent exited-before-term exits-on-term denied-term exits-on-kill denied-kill; do
    live=1 expected=0
    [ "$CASE" != absent ] || live=0
    case "$CASE" in denied-*) expected=1 ;; esac
    : > "$RUN/core.pid"
    : > "$WORK/signals"
    actual=0
    stop_core || actual=$?
    [ "$actual" = "$expected" ]
    if [ "$expected" = 0 ]; then [ ! -f "$RUN/core.pid" ]; else [ -f "$RUN/core.pid" ]; fi
    echo "PASS stop-core: $CASE"
done
