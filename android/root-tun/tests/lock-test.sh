#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
TEST_PIDS=''
finish() {
    for test_pid in $TEST_PIDS; do kill "$test_pid" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap finish EXIT
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" \
    -e '/^export PATH=/d' -e '/^safe_tree || exit 1/,$d' \
    "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/functions.sh"
mkdir -p "$WORK/runtime/run"
cat > "$WORK/contender.sh" <<'CONTENDER'
#!/bin/sh
set -eu
. "$1/functions.sh"
IDENTITY="$$ $(ticks "$$") $BOOT"
touch "$1/ready.$2"
while [ ! -f "$1/go" ]; do sleep 0.01; done
if lock control; then
    if ! mkdir "$1/critical"; then touch "$1/overlap"; fi
    printf '%s\n' "$IDENTITY" >> "$1/winners"
    touch "$1/attempted.$2"
    while [ ! -f "$1/release" ]; do sleep 0.01; done
    unlock control
else
    touch "$1/attempted.$2"
fi
CONTENDER
wait_file() {
    attempt=0
    while [ ! -f "$1" ]; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 300 ] || exit 1
        sleep 0.01
    done
}
for round in 1 2 3 4 5 6 7 8 9 10; do
    rm -f "$WORK/"ready.* "$WORK/"attempted.* "$WORK/go" "$WORK/release" "$WORK/winners"
    rmdir "$WORK/critical" 2>/dev/null || true
    printf '999999 %s previous-boot\n' "$round" > "$WORK/runtime/run/control.lock"
    sh "$WORK/contender.sh" "$WORK" 1 & first=$!
    sh "$WORK/contender.sh" "$WORK" 2 & second=$!
    TEST_PIDS="$first $second"
    wait_file "$WORK/ready.1"
    wait_file "$WORK/ready.2"
    touch "$WORK/go"
    wait_file "$WORK/attempted.1"
    wait_file "$WORK/attempted.2"
    [ ! -f "$WORK/overlap" ]
    [ "$(wc -l < "$WORK/winners")" -eq 1 ]
    [ "$(cat "$WORK/runtime/run/control.lock")" = "$(cat "$WORK/winners")" ]
    touch "$WORK/release"
    wait "$first"
    wait "$second"
    TEST_PIDS=''
done
echo 'PASS concurrent stale lock reapers preserve exactly one owner across ten races'
# shellcheck source=/dev/null
. "$WORK/functions.sh"
IDENTITY="$$ $(ticks "$$") $BOOT"
stale_identity='999999 100 previous-boot'
printf '%s\n' "$stale_identity" > "$RUN/control.lock"
stale_key=$(printf '%s' "$stale_identity" | cksum | awk '{print $1 "-" $2}')
printf '%s\n' "$stale_identity" > "$RUN/control.reaper.$stale_key.lock"
lock control
[ "$(cat "$RUN/control.lock")" = "$IDENTITY" ]
[ ! -f "$RUN/control.reaper.$stale_key.lock" ]
unlock control
echo 'PASS a crashed stale-lock reaper is itself reclaimable'
mkdir "$RUN/owner.lock"
printf '%s\n' "$IDENTITY" > "$RUN/supervisor.pid"
if claim_owner; then exit 1; fi
[ -d "$RUN/owner.lock" ]
printf '999999 1 previous-boot\n' > "$RUN/supervisor.pid"
claim_owner
[ -f "$RUN/owner.lock" ]
unlock owner
echo 'PASS legacy directory owner lock is reclaimed only after the supervisor is dead'
