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
    -e '/^export PATH=/d' -e '/^safe_tree || exit 1/,$d' \
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
# Fixed KernelSU v3 ARM64 fixture: header + app_profile, UID=10000, allow_su=1.
dd if=/dev/zero of="$WORK/ksu/.allowlist" bs=784 count=1 2>/dev/null
printf '\125\123\113\177\003\000\000\000\003\000\000\000com.follow.clash.root\000' |
    dd of="$WORK/ksu/.allowlist" conv=notrunc 2>/dev/null
printf '\020\047\000\000\001' | dd of="$WORK/ksu/.allowlist" bs=1 seek=268 conv=notrunc 2>/dev/null
[ "$(manager_authorization)" = granted ]
printf '\000' | dd of="$WORK/ksu/.allowlist" bs=1 seek=272 conv=notrunc 2>/dev/null
[ "$(manager_authorization)" = denied ]
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
echo apatch > "$R/config/root.manager"
printf '%s\n' 'pkg,exclude,allow,uid,to_uid,sctx' 'com.follow.clash.root,0,1,10000,0,u:r:su:s0' > "$WORK/ap/package_config"
[ "$(manager_authorization)" = granted ]
sed 's/,0,1,10000/,0,0,10000/' "$WORK/ap/package_config" > "$WORK/ap/next"
mv "$WORK/ap/next" "$WORK/ap/package_config"
[ "$(manager_authorization)" = denied ]
echo malformed > "$WORK/ap/package_config"
[ "$(manager_authorization)" = unknown ]
echo 'PASS APatch exact package/UID grant/revoke and unknown format'
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
echo 0 > "$STATE/revoked-since"
boot_seconds() { echo 600; }
boot_seconds >/dev/null
start_probe() { return 0; }
start_probe auth
watchdog
[ ! -f "$RUN/watchdog.pid" ] && [ ! -f "$STATE/owned" ]
grep -q 'revocation monitoring expired' "$R/logs/watchdog.log"
echo 'PASS revoked watchdog exits after ten minutes without retaining network ownership'
