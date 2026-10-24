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
export FAKE_NET="$WORK/net"
export PATH="$WORK/bin:$PATH"
TEST_PATH=$PATH
mkdir -p "$FAKE_NET" "$WORK/bin" "$WORK/ksu" "$WORK/ap" "$WORK/service.d"
for stub in pm log ip iptables ip6tables iptables-save ip6tables-save settings nc; do
    ln -s "$TESTS/network-stub.sh" "$WORK/bin/$stub"
done
cat > "$WORK/bin/magisk" <<'MAGISK'
#!/bin/sh
case "$(cat "$FAKE_NET/magisk")" in
    timeout) sleep 3 ;;
    fail) exit 1 ;;
    *) cat "$FAKE_NET/magisk" ;;
esac
MAGISK
chmod +x "$WORK/bin/magisk"
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" \
    -e '/^export PATH=/d' -e '/^safe_tree || exit 1/,$d' -e 's|/system/bin/sh|/bin/sh|g' \
    -e "s|/data/adb/service.d|$WORK/service.d|g" \
    "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/runtime.sh"
sed -e "s|/data/adb/ksu|$WORK/ksu|g" -e "s|/data/adb/ap|$WORK/ap|g" \
    "$TESTS/../../app/src/main/assets/root-tun/authorization.sh" > "$WORK/authorization.sh"
# shellcheck source=/dev/null
. "$WORK/runtime.sh"
# shellcheck source=/dev/null
. "$WORK/authorization.sh"
IDENTITY="$$ $(ticks "$$") $BOOT"
export IDENTITY
mkdir -p "$STATE" "$RUN" "$R/logs" "$R/tmp" "$R/config"
printf '10000\n' > "$R/config/app.uid"
echo kernelsu > "$R/config/root.manager"
mkdir -p "$R/scripts"
sed -e "s|^R=/data/adb/flclash-root$|R=$R|" -e '/^export PATH=/d' -e 's|/system/bin/sh|/bin/sh|g' \
    -e 's/ = 0 ]/ = '"$(id -u)"' ]/' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$R/scripts/runtime.sh"
cp "$WORK/authorization.sh" "$R/scripts/authorization.sh"
# Fixed KernelSU v3 ARM64 fixture: header + app_profile, UID=10000, allow_su=1.
dd if=/dev/zero of="$WORK/ksu/.allowlist" bs=784 count=1 2>/dev/null
printf '\125\123\113\177\003\000\000\000\003\000\000\000com.follow.clash.root\000' |
    dd of="$WORK/ksu/.allowlist" conv=notrunc 2>/dev/null
printf '\020\047\000\000\001' | dd of="$WORK/ksu/.allowlist" bs=1 seek=268 conv=notrunc 2>/dev/null
[ "$(manager_authorization)" = granted ]
printf '\000' | dd of="$WORK/ksu/.allowlist" bs=1 seek=272 conv=notrunc 2>/dev/null
[ "$(manager_authorization)" = denied ]
sh "$R/scripts/runtime.sh" retain-auth-evidence
grep -q '^header: 85 83 75 127 3 0 0 0' "$R/logs/allowlist-denied.txt"
grep -q '^app-record offset=8:' "$R/logs/allowlist-denied.txt"
grep -q 'collector-exit=0' "$R/logs/allowlist-denied.txt"
printf '\011' | dd of="$WORK/ksu/.allowlist" bs=1 seek=4 conv=notrunc 2>/dev/null
[ "$(manager_authorization)" = unknown ]
echo 'PASS KernelSU grant/revoke; unknown binary version is not denial (device ABI pending W3)'
echo magisk > "$R/config/root.manager"
echo 'policy=2|until=0' > "$FAKE_NET/magisk"
[ "$(manager_authorization)" = granted ]
echo 'policy=1|until=0' > "$FAKE_NET/magisk"
[ "$(manager_authorization)" = denied ]
: > "$FAKE_NET/magisk"
[ "$(manager_authorization)" = denied ]
echo 'policy=2|until=1' > "$FAKE_NET/magisk"
[ "$(manager_authorization)" = denied ]
for result in fail timeout malformed; do
    echo "$result" > "$FAKE_NET/magisk"
    [ "$(manager_authorization)" = unknown ]
done
echo 'PASS Magisk explicit policy and expiry; failure/timeout/malformed remain unknown'
(
    mkdir "$WORK/probe-bin"
    cat > "$WORK/probe-bin/nc" <<'NC'
#!/bin/sh
sleep 3
NC
    chmod +x "$WORK/probe-bin/nc"
    export PATH="$WORK/probe-bin:$TEST_PATH"
    printf '%s\n' '12345 probe-token' > "$R/config/app-auth"
    echo 'policy=1|until=0' > "$FAKE_NET/magisk"
    probe_started=$(boot_ms)
    sh "$R/scripts/runtime.sh" probe-auth bounded
    probe_elapsed=$(($(boot_ms) - probe_started))
    [ "$probe_elapsed" -lt 1800 ]
    [ "$(cat "$RUN/auth.result")" = 'bounded denied unknown' ]
    echo timeout > "$FAKE_NET/magisk"
    sh "$R/scripts/runtime.sh" probe-auth timeout
    [ "$(cat "$RUN/auth.result")" = 'timeout unknown unknown' ]
)
rm -f "$RUN/auth.result" "$R/config/app-auth"
echo 'PASS real probe worker overlaps manager/App timeouts within 1.8s; timed-out manager remains unknown'
echo apatch > "$R/config/root.manager"
printf '%s\n' 'pkg,exclude,allow,uid,to_uid,sctx' 'com.follow.clash.root,0,1,10000,0,u:r:su:s0' > "$WORK/ap/package_config"
[ "$(manager_authorization)" = granted ]
sed 's/,0,1,10000/,0,0,10000/' "$WORK/ap/package_config" > "$WORK/ap/next"
mv "$WORK/ap/next" "$WORK/ap/package_config"
[ "$(manager_authorization)" = denied ]
echo malformed > "$WORK/ap/package_config"
[ "$(manager_authorization)" = unknown ]
echo 'PASS APatch exact package/UID grant/revoke and unknown format'
# shellcheck disable=SC2329
(
    mkdir "$WORK/status-bin"
    cat > "$WORK/status-bin/nc" <<'NC'
#!/bin/sh
cat > "$FAKE_NET/status-probe"
NC
    chmod +x "$WORK/status-bin/nc"
    PATH="$WORK/status-bin:$TEST_PATH"
    printf '%s\n' '12345 test-token' > "$R/config/app-auth"
    printf '%s\n' 'running -' > "$STATE/status"
    : > "$STATE/auth-status"
    printf '%s\n' off > "$STATE/private-dns"
    printf '%s\n' com.follow.clash.root > "$R/config/app.package"
    boot_ms() { echo 123456; }
    runtime_session_report() { printf 'session:test-session\nstop:active\n'; }
    [ "$(app_authorization)" = unknown ]
    read -r operation nonce signature payload < "$FAKE_NET/status-probe"
    [ "$operation" = probe ]
    case "$payload" in running\ -*'|bootMs:123456') ;; *) exit 1 ;; esac
    expected=$(printf '%s:%s:%s' test-token "$nonce" "$payload" | sha256sum | cut -d' ' -f1)
    [ "$signature" = "$expected" ]
)
rm -f "$STATE/auth-status"
echo 'PASS signed runtime report includes bootMs in the authenticated payload'
denied_count=0
record_authorization denied unknown
[ "$denied_count" -eq 1 ]
record_authorization unknown unknown
[ "$denied_count" -eq 0 ]
[ ! -f "$STATE/auth-status" ]
claim_owner
install_rules
unlock owner
touch "$FAKE_NET/tun"
sleep 1000 &
core_pid=$!
TEST_PIDS="$core_pid"
printf '%s %s %s\n' "$core_pid" "$(ticks "$core_pid")" "$BOOT" > "$RUN/core.pid"
printf '%s\n' '# flclash-root service.d v2' > "$WORK/service.d/flclash-root.sh"
printf foreign > "$WORK/service.d/foreign.sh"
echo 1 > "$R/config/root-tun-enabled"
echo 1 > "$R/config/autostart-enabled"
post_notification() { printf '%s\n' "$1" >> "$R/logs/test-notifications"; }
cleanup_bounded() { cleanup; }
detach() { return 0; }
record_authorization denied unknown
record_authorization denied unknown
wait "$core_pid" 2>/dev/null || true
[ "$(cat "$STATE/status")" = 'failed ROOT_PERMISSION_REVOKED' ]
[ "$(cat "$STATE/auth-status")" = revoked ]
[ ! -f "$STATE/owned" ] && [ ! -f "$FAKE_NET/tun" ] && [ ! -s "$R/logs/restore-diff.txt" ]
[ ! -f "$WORK/service.d/flclash-root.sh" ] && [ -f "$WORK/service.d/foreign.sh" ]
[ "$(cat "$R/config/autostart-enabled")" = 0 ]
echo 'PASS two confirmed revocations clean before reporting failed/revoked, disable autostart and preserve foreign entry'
rm -f "$STATE/auth-status" "$RUN/stop"
printf '%s\n' '# foreign entry' > "$WORK/service.d/flclash-root.sh"
revoke_runtime AUTOSTART_ROOT_REVOKED
[ "$(cat "$STATE/status")" = 'failed AUTOSTART_ROOT_REVOKED' ]
[ -f "$WORK/service.d/flclash-root.sh" ]
echo 'PASS boot revocation uses appendix B code and leaves unknown entry untouched'

rm -f "$STATE/auth-status" "$RUN/stop"
claim_owner
install_rules
unlock owner
touch "$FAKE_NET/block-cleanup"
if revoke_runtime ROOT_PERMISSION_REVOKED; then exit 1; fi
[ "$(cat "$STATE/status")" = 'stopping CLEANUP_FAILED' ]
[ "$(cat "$STATE/revocation-code")" = ROOT_PERMISSION_REVOKED ]
rm -f "$FAKE_NET/block-cleanup"
revoke_runtime "$(cat "$STATE/revocation-code")"
[ "$(cat "$STATE/status")" = 'failed ROOT_PERMISSION_REVOKED' ]
echo 'PASS cleanup retries retain revocation cause and report failed only after rules are gone'
# shellcheck disable=SC2329
(
    rm -f "$STATE/auth-status" "$STATE/revocation-code" "$RUN/stop"
    printf '%s\n' 'running -' > "$STATE/status"
    touch "$STATE/owned"
    [ "$(authorization_interval)" -eq 1 ]
    touch "$RUN/stop"
    [ "$(authorization_interval)" -eq 1 ]
    rm -f "$STATE/owned"
    printf '%s\n' 'stopping CLEANUP_FAILED' > "$STATE/status"
    [ "$(authorization_interval)" -eq 1 ]
    rm -f "$RUN/stop"
    printf '%s\n' 'running -' > "$STATE/status"
    touch "$STATE/owned"
    simulated_time=0
    boot_seconds() { echo "$simulated_time"; }
    heartbeat() { return 0; }
    fresh() { return 0; }
    start_probe() {
        [ "$1" != auth ] || printf '%s\n' "$simulated_time" >> "$WORK/auth-checks"
    }
    sleep() {
        simulated_time=$((simulated_time + 1))
        case "$simulated_time" in
            5)
                touch "$RUN/stop"
                rm -f "$STATE/owned"
                printf '%s\n' 'disabled -' > "$STATE/status"
                ;;
            35)
                rm -f "$RUN/stop"
                touch "$STATE/owned"
                printf '%s\n' 'running -' > "$STATE/status"
                ;;
            40) exit 0 ;;
        esac
    }
    watchdog
)
printf '%s\n' 0 1 2 3 4 5 20 35 36 37 38 39 > "$WORK/expected-auth-checks"
cmp "$WORK/expected-auth-checks" "$WORK/auth-checks"
echo 'PASS watchdog authorization probes use 15 seconds after proxyStop and resume 1 second when running'
# shellcheck disable=SC2329
(
    rm -f "$STATE/revocation-code" "$STATE/auth-status" "$STATE/revoked-since" "$RUN/stop"
    printf '%s\n' 'running -' > "$STATE/status"
    elapsed_ms=0
    clock_file=$WORK/latency-clock
    echo 0 > "$clock_file"
    boot_ms() { cat "$clock_file"; }
    boot_seconds() { echo "$(($(cat "$clock_file") / 1000))"; }
    fresh() { return 0; }
    heartbeat() { return 0; }
    pending_at=0
    probe_number=0
    start_probe() {
        [ "$1" = auth ] || return 0
        [ "$pending_at" -eq 0 ] || return 0
        [ "$elapsed_ms" -ge 1000 ] || return 0
        probe_number=$((probe_number + 1))
        printf '%s\n' "$probe_number" > "$RUN/auth-probe.id"
        pending_at=$((elapsed_ms + 1000))
    }
    sleep() {
        case "$1" in 0.25) elapsed_ms=$((elapsed_ms + 250)) ;; *) elapsed_ms=$((elapsed_ms + 1000)) ;; esac
        echo "$elapsed_ms" > "$clock_file"
        if [ "$elapsed_ms" -eq 2500 ]; then lock control; fi
        if [ "$elapsed_ms" -ge 4500 ]; then unlock control; fi
        if [ "$pending_at" -ne 0 ] && [ "$elapsed_ms" -ge "$pending_at" ]; then
            printf '%s denied unknown\n' "$probe_number" > "$RUN/auth.result"
            pending_at=0
        fi
        if [ "$elapsed_ms" -gt 14500 ]; then echo 'FAIL revocation exceeded budget' >&2; exit 1; fi
    }
    cleanup() { elapsed_ms=$((elapsed_ms + 3000)); echo "$elapsed_ms" > "$clock_file"; rm -f "$STATE/owned"; }
    notify_app_cleanup() {
        [ "$(cat "$STATE/status")" = 'failed ROOT_PERMISSION_REVOKED' ]
        display_ms=$((elapsed_ms + 250))
        [ "$display_ms" -le 12500 ]
        printf 'PASS worst-phase revoke with 1s parallel probes, control contention, 3s cleanup and 250ms App poll: %sms (<15s)\n' "$display_ms"
        exit 0
    }
    watchdog
)
rm -f "$STATE/owned" "$RUN/stop"
printf '%s\n' revoked > "$STATE/auth-status"
printf '%s\n' 'failed ROOT_PERMISSION_REVOKED' > "$STATE/status"
echo 0 > "$STATE/revoked-since"
boot_seconds() { echo 600; }
boot_seconds >/dev/null
start_probe() { return 0; }
start_probe auth
watchdog
[ ! -f "$RUN/watchdog.pid" ] && [ ! -f "$STATE/owned" ]
grep -q 'revocation monitoring expired' "$R/logs/watchdog.log"
echo 'PASS revoked watchdog exits after ten minutes without retaining network ownership'
