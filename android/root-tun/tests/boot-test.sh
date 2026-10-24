#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" \
    -e '/^export PATH=/d' -e '/^safe_tree || exit 1/,$d' \
    -e 's|/system/bin/sh|/bin/sh|g' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/functions.sh"
# shellcheck source=/dev/null
. "$WORK/functions.sh"
IDENTITY="$$ $(ticks "$$") $BOOT"
export IDENTITY
mkdir -p "$RUN" "$STATE" "$R/logs" "$R/config" "$R/bin" "$R/scripts" "$R/tmp"
FAKE_NOW=0
boot_seconds() { cat "$R/clock"; }
sleep() {
    FAKE_NOW=$((FAKE_NOW + $1))
    echo "$FAKE_NOW" > "$R/clock"
    if [ "${NETWORK_READY_AT:-0}" -gt 0 ] && [ "$FAKE_NOW" -ge "$NETWORK_READY_AT" ]; then rm -f "$R/network-offline"; fi
}
echo 0 > "$R/clock"
getprop() {
    case "$1" in
        sys.boot_completed) echo "${BOOT_COMPLETE:-1}" ;;
        sys.user.0.ce_available) [ "${CE_AVAILABLE:-false}" != failure ] || return 1; echo "${CE_AVAILABLE:-false}" ;;
        *) return 1 ;;
    esac
}
cat > "$WORK/am" <<'AM'
#!/bin/sh
[ "$*" = 'get-started-user-state 0' ] || exit 64
case "${AM_STATE:-RUNNING_UNLOCKED}" in
    missing) exit 127 ;;
    delayed)
        if [ "$(cat "$R/clock")" -lt 4 ]; then echo RUNNING_LOCKED; else echo RUNNING_UNLOCKED; fi
        ;;
    *) echo "${AM_STATE:-RUNNING_UNLOCKED}" ;;
esac
AM
chmod +x "$WORK/am"
export PATH="$WORK:$PATH" R
ensure_watchdog() { return 0; }
package_status() { echo present; }
cleanup() { return 0; }
cleanup_bounded() { cleanup; }
post_notification() { printf '%s\n' "$1" >> "$R/notified"; }
context_tools() { return 0; }
cat > "$WORK/ip" <<'IP'
#!/bin/sh
[ ! -f "$R/network-offline" ] || exit 0
echo 'default via 192.0.2.1 dev wlan0 table 1001'
IP
chmod +x "$WORK/ip"
manager_authorization() { echo granted; }
printf 1 > "$R/config/root-tun-enabled"
printf 1 > "$R/config/autostart-enabled"
write_settings
printf config > "$R/config/config.yaml"
printf '#!/bin/sh\nexit 0\n' > "$CORE"
chmod +x "$CORE"
cat > "$R/scripts/runtime.sh" <<'START'
#!/bin/sh
[ "$1" = start ] || exit 0
printf '%s\n' start >> "$(dirname "$0")/../starts"
printf '%s\n' 'running -' > "$(dirname "$0")/../state/status"
START
mkdir "$RUN/boot-00000000-0000-0000-0000-000000000001" "$RUN/boot-foreign"
bootstrap
unlock boot
[ ! -d "$RUN/boot-00000000-0000-0000-0000-000000000001" ] && [ -d "$RUN/boot-foreign" ]
bootstrap
unlock boot
[ "$(wc -l < "$R/starts" | tr -d ' ')" -eq 1 ]
[ "$(cat "$RUN/boot-id")" = "$BOOT" ]
echo 'PASS repeated boot starts once; fixed boot-id file avoids accumulated directories'
stop_runtime
[ "$(cat "$R/config/autostart-enabled")" = 1 ]
BOOT=simulated-next-boot
bootstrap
unlock boot
[ "$(wc -l < "$R/starts" | tr -d ' ')" -eq 2 ]
echo 'PASS proxyStop keeps autostart and a new boot starts again'
rm -f "$RUN/boot-id" "$R/starts"
printf 0 > "$R/config/root-tun-enabled"
write_settings
bootstrap
unlock boot
[ ! -f "$R/starts" ]
echo 'PASS disabled setting prevents start'
printf invalid > "$R/config/settings.json"
if bootstrap; then exit 1; fi
unlock boot
grep -q 'failed AUTOSTART_FAILED' "$STATE/status"
[ ! -f "$R/starts" ]
echo 'PASS malformed settings fail open with AUTOSTART_FAILED'
BOOT_COMPLETE=0
if bootstrap; then exit 1; fi
unlock boot
[ "$FAKE_NOW" -eq 120 ]
echo 'PASS boot_completed wait is bounded'
BOOT_COMPLETE=1
printf 1 > "$R/config/root-tun-enabled"
write_settings
touch "$R/network-offline"
if bootstrap; then exit 1; fi
unlock boot
[ "$FAKE_NOW" -eq 168 ]
echo 'PASS dependency wait has 48 second budget; seven checks at eight second intervals'
rm -f "$R/network-offline"
rm -f "$RUN/boot-id"
FAKE_NOW=0
echo 0 > "$R/clock"
export AM_STATE=delayed
bootstrap
unlock boot
[ "$FAKE_NOW" -eq 4 ]
echo 'PASS RUNNING_LOCKED waits until am reports RUNNING_UNLOCKED'
export AM_STATE=missing CE_AVAILABLE=true
user_unlocked
rm -f "$RUN/boot-id"
bootstrap
unlock boot
echo 'PASS missing am falls back to sys.user.0.ce_available=true'
export CE_AVAILABLE=failure
FAKE_NOW=0
echo 0 > "$R/clock"
if bootstrap; then exit 1; fi
unlock boot
[ "$FAKE_NOW" -eq 300 ]
grep -q 'failed AUTOSTART_FAILED' "$STATE/status"
echo 'PASS failed am and getprop time out with AUTOSTART_FAILED'

export AM_STATE=RUNNING_UNLOCKED CE_AVAILABLE=true
rm -f "$RUN/boot-id" "$R/starts" "$R/notified" "$R/logs/boot.log"
FAKE_NOW=0
echo 0 > "$R/clock"
NETWORK_READY_AT=16
touch "$R/network-offline"
bootstrap
unlock boot
[ "$FAKE_NOW" -eq 16 ]
[ "$(grep -c 'network attempt=' "$R/logs/boot.log")" -eq 3 ]
[ "$(wc -l < "$R/starts")" -eq 1 ]
[ ! -f "$R/notified" ]
echo 'PASS delayed network readiness retries at 0/8/16 seconds and starts exactly once without a failure notification'
NETWORK_READY_AT=0
FAKE_NOW=0
echo 0 > "$R/clock"
rm -f "$RUN/boot-id" "$R/starts" "$R/logs/boot.log"
touch "$R/network-offline"
if bootstrap; then exit 1; fi
unlock boot
[ "$FAKE_NOW" -eq 48 ]
[ "$(grep -c 'network attempt=' "$R/logs/boot.log")" -eq 7 ]
[ ! -f "$R/starts" ]
[ "$(cat "$R/notified")" = AUTOSTART_FAILED ]
[ "$(cat "$STATE/status")" = 'failed AUTOSTART_FAILED' ]
echo 'PASS seven offline attempts exhaust budget without network takeover; persistent AUTOSTART_FAILED and notification emitted'
[ ! -f "$STATE/owned" ]
[ "$(authorization_interval)" -eq 15 ]
echo 'PASS AUTOSTART_FAILED watchdog authorization probes use the 15 second idle interval'
