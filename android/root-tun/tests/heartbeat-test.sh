#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" -e '/^export PATH=/d' \
    -e 's|^BOOT=$(cat /proc/sys/kernel/random/boot_id)$|BOOT=test-boot|' \
    -e '/^safe_tree || exit 1/,$d' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/functions.sh"
. "$WORK/functions.sh"
mkdir -p "$RUN"
now=100
boot_seconds() { echo "$now"; }
fresh() { [ -f "$RUN/fresh" ]; }
alive() { [ -f "$1" ]; }
printf '123 456 boot\n' > "$RUN/supervisor.pid"
echo first > "$RUN/supervisor.heartbeat"
if stalled supervisor; then exit 1; fi
now=102
if stalled supervisor; then exit 1; fi
now=3600
if stalled supervisor; then exit 1; fi
now=3602
if stalled supervisor; then exit 1; fi
echo resumed > "$RUN/supervisor.heartbeat"
now=3603
if stalled supervisor; then exit 1; fi
touch "$RUN/fresh"
if stalled supervisor; then exit 1; fi
[ ! -f "$RUN/supervisor.suspect" ]
echo 'PASS sleeping workers get a new observation window and a resumed heartbeat clears suspicion'
rm "$RUN/fresh"
now=4000
if stalled supervisor; then exit 1; fi
for now in 4002 4004 4006 4008; do
    if stalled supervisor; then exit 1; fi
done
now=4010
stalled supervisor
echo 'PASS an unchanged live worker is reclaimed after continuously observed missed heartbeats'
rm "$RUN/supervisor.pid"
stalled supervisor
[ ! -f "$RUN/supervisor.suspect" ]
echo 'PASS a dead worker is recovered immediately without the wake-up grace period'
