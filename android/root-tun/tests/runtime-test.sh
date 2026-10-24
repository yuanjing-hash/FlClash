#!/bin/sh
set -eu
SOURCE=$(CDPATH='' cd -- "$(dirname "$0")/../../app/src/main/assets/root-tun" && pwd)
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
export FAKE_NET="$WORK/net"
mkdir -p "$FAKE_NET" "$WORK/bin"
TEST_PIDS=''
finish() {
    for test_pid in $TEST_PIDS; do kill "$test_pid" 2>/dev/null || true; done
    if [ -d "$WORK/runtime/run" ]; then
        for pid_file in "$WORK/runtime/run/"*.pid; do
            [ -f "$pid_file" ] || continue
            read -r test_pid _ < "$pid_file"
            kill "$test_pid" 2>/dev/null || true
        done
    fi
    rm -rf "$WORK"
}
trap finish EXIT
trap 'exit 1' INT TERM
for stub in ip iptables ip6tables iptables-save ip6tables-save settings nc pm log; do
    ln -s "$TESTS/network-stub.sh" "$WORK/bin/$stub"
done
export PATH="$WORK/bin:$PATH"
R=$WORK/runtime
mkdir -p "$R/scripts" "$R/run" "$R/state" "$R/logs" "$R/config" "$R/bin" "$R/tmp"
sed -e "s|^R=/data/adb/flclash-root$|R=$R|" \
    -e 's/ = 0 ]/ = '"$(id -u)"' ]/' -e '/^export PATH=/d' -e 's|/system/bin/sh|/bin/sh|g' \
    -e 's|! -c /dev/net/tun|! -c /dev/null|' "$SOURCE/runtime.sh" > "$R/scripts/runtime.sh"
cp "$SOURCE/authorization.sh" "$R/scripts/authorization.sh"
cat > "$R/bin/mihomo" <<'CORE'
#!/bin/sh
trap 'rm -f "$FAKE_NET/tun"; exit 0' TERM INT
printf '%s\n' start >> "$FAKE_NET/core-starts"
touch "$FAKE_NET/tun"
while :; do sleep 0.1; done
CORE
chmod +x "$R/bin/mihomo"
printf 12345 > "$R/config/controller.port"
: > "$R/config/health.http"
run() { sh "$R/scripts/runtime.sh" "$@"; }
wait_for() {
    wait_attempt=0
    until "$@"; do
        wait_attempt=$((wait_attempt + 1))
            if [ "$wait_attempt" -gt 400 ]; then
            echo "FAIL timeout: $1" >&2
            cat "$R/state/status" "$R/logs/"*.log 2>/dev/null >&2 || true
            exit 1
        fi
        sleep 0.1
    done
}
pid_of() { cut -d' ' -f1 "$R/run/$1.pid"; }
is_running() { [ "$(cut -d' ' -f1 "$R/state/status" 2>/dev/null)" = running ]; }
ready() { is_running && [ -f "$R/run/watchdog.heartbeat" ]; }
changed() { [ -f "$R/run/$1.pid" ] && [ "$(pid_of "$1")" != "$2" ] && ready; }
stopped() { [ ! -f "$R/run/watchdog.pid" ] && [ ! -f "$R/run/supervisor.pid" ] && [ ! -f "$R/run/core.pid" ]; }
run start
wait_for ready
status=$(run status)
report_ms=$(printf '%s\n' "$status" | sed -n 's/^bootMs://p')
case "$report_ms" in ''|*[!0-9]*) exit 1 ;; esac
echo 'PASS runtime status includes bootMs'
supervisor=$(pid_of supervisor)
watchdog=$(pid_of watchdog)
core=$(pid_of core)
TEST_PIDS="$TEST_PIDS $supervisor $watchdog $core"
run start
sleep 0.2
[ "$supervisor" = "$(pid_of supervisor)" ]
[ "$watchdog" = "$(pid_of watchdog)" ]
[ "$core" = "$(pid_of core)" ]
echo 'PASS singleton start'
touch "$FAKE_NET/slow-settings"
wait_for test -f "$FAKE_NET/settings-delayed"
sleep 7
[ "$supervisor" = "$(pid_of supervisor)" ] && [ "$watchdog" = "$(pid_of watchdog)" ]
if grep -q 'supervisor takeover' "$R/logs/watchdog.log"; then exit 1; fi
rm -f "$FAKE_NET/slow-settings"
echo 'PASS supervisor rounds of 2.5 seconds do not trigger watchdog takeover'
echo timeout > "$FAKE_NET/package"
sleep 3
[ "$watchdog" = "$(pid_of watchdog)" ] && [ "$core" = "$(pid_of core)" ]
rm -f "$FAKE_NET/package"
echo 'PASS slow pm does not stall watchdog heartbeat'
kill -TERM "$watchdog"
wait_for changed watchdog "$watchdog"
[ "$core" = "$(pid_of core)" ]
watchdog=$(pid_of watchdog)
TEST_PIDS="$TEST_PIDS $watchdog"
echo 'PASS watchdog normal exit leaves running service intact'
kill -KILL "$watchdog"
wait_for changed watchdog "$watchdog"
[ "$core" = "$(pid_of core)" ]
watchdog=$(pid_of watchdog)
TEST_PIDS="$TEST_PIDS $watchdog"
echo 'PASS watchdog respawn without core restart'
kill -KILL "$supervisor"
wait_for changed supervisor "$supervisor"
[ "$core" = "$(pid_of core)" ]
supervisor=$(pid_of supervisor)
TEST_PIDS="$TEST_PIDS $supervisor"
echo 'PASS supervisor takeover without core restart'
touch "$FAKE_NET/health-timeout"
: > "$FAKE_NET/calls"
kill -KILL "$supervisor"
wait_for test -f "$FAKE_NET/health-delayed"
sleep 4
[ -f "$R/state/owned" ] && [ -f "$FAKE_NET/iptables.guard" ]
if grep -E '(-D OUTPUT|-X FCR_OUTPUT|rule del|route flush|link delete)' "$FAKE_NET/calls"; then exit 1; fi
rm -f "$FAKE_NET/health-timeout"
wait_for changed supervisor "$supervisor"
[ "$core" = "$(pid_of core)" ]
supervisor=$(pid_of supervisor)
TEST_PIDS="$TEST_PIDS $supervisor"
echo 'PASS slow health checks retry behind the guard and recover without restarting core'
: > "$FAKE_NET/calls"
kill -KILL "$core"
wait_for changed core "$core"
core=$(pid_of core)
TEST_PIDS="$TEST_PIDS $core"
if grep -E '(-D OUTPUT|-X FCR_OUTPUT|rule del|route flush|link delete)' "$FAKE_NET/calls"; then exit 1; fi
# The guard was installed on first start and survives recovery without a flush.
[ -f "$FAKE_NET/iptables.chain" ] && [ -f "$FAKE_NET/ip6tables.chain" ]
echo 'PASS core recovery preserves takeover and leak protection'
kill -KILL "$supervisor" "$core"
wait_for grep -q "failed CORE_RECOVERY_FAILED" "$R/state/status"
[ ! -f "$R/state/owned" ] && [ ! -f "$FAKE_NET/tun" ]
[ ! -s "$R/logs/restore-diff.txt" ]
echo 'PASS supervisor and core loss cleans network'
run cleanup
wait_for test ! -f "$R/run/watchdog.pid"
run start
wait_for is_running
sleep 1000 &
boot_pid=$!
TEST_PIDS="$TEST_PIDS $boot_pid"
boot_ticks=$(sed 's/.*) //' "/proc/$boot_pid/stat" | awk '{print $20}')
printf '%s %s %s\n' "$boot_pid" "$boot_ticks" "$(cat /proc/sys/kernel/random/boot_id)" > "$R/run/boot.lock"
run stop
wait "$boot_pid" 2>/dev/null || true
wait_for test ! -f "$R/run/supervisor.pid"
[ ! -f "$R/run/core.pid" ] && [ -f "$R/run/watchdog.pid" ]
run cleanup
wait_for stopped
echo 'PASS proxyStop keeps uninstall monitor; explicit cleanup removes all managed processes'
mkdir "$R/run/owner.lock"
printf '999999 1 previous-boot\n' > "$R/run/supervisor.pid"
run start
wait_for ready
run cleanup
wait_for stopped
mkdir "$R/run/owner.lock"
run cleanup
[ ! -d "$R/run/owner.lock" ]
echo 'PASS legacy directory owner lock after reboot permits start and stop'
run start
wait_for ready
supervisor=$(pid_of supervisor)
watchdog=$(pid_of watchdog)
core=$(pid_of core)
TEST_PIDS="$TEST_PIDS $supervisor $watchdog $core"
kill -KILL "$supervisor" "$watchdog"
rm -f "$R/run/owner.lock" "$R/run/generation" "$R/run/supervisor.heartbeat" "$FAKE_NET/iptables.guard"
mkdir "$R/run/owner.lock"
sleep 1000 &
legacy_pid=$!
TEST_PIDS="$TEST_PIDS $legacy_pid"
legacy_ticks=$(sed 's/.*) //' "/proc/$legacy_pid/stat" | awk '{print $20}')
printf '%s %s %s\n' "$legacy_pid" "$legacy_ticks" "$(cat /proc/sys/kernel/random/boot_id)" > "$R/run/supervisor.pid"
run start
wait_for changed supervisor "$legacy_pid"
[ "$core" = "$(pid_of core)" ] && [ -f "$FAKE_NET/iptables.guard" ]
run stop
echo 'PASS legacy supervisor handoff preserves core and installs missing recovery guard'

run start
wait_for ready
for crash_number in 1 2; do
    core=$(pid_of core)
    kill -KILL "$core"
    wait_for changed core "$core"
    if [ "$crash_number" -eq 1 ]; then
        supervisor=$(pid_of supervisor)
        kill -KILL "$supervisor"
        wait_for changed supervisor "$supervisor"
    fi
done
kill -KILL "$(pid_of core)"
wait_for grep -q 'failed CORE_CRASH_LOOP' "$R/state/status"
[ ! -f "$R/state/owned" ] && [ ! -f "$FAKE_NET/tun" ]
run stop
echo 'PASS third core crash in five minutes trips circuit breaker across supervisor takeover'
