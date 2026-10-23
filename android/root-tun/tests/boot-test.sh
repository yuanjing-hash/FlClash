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
mkdir -p "$RUN" "$STATE" "$R/logs" "$R/config" "$R/bin" "$R/scripts"
FAKE_NOW=0
boot_seconds() { cat "$R/clock"; }
sleep() { FAKE_NOW=$((FAKE_NOW + $1)); echo "$FAKE_NOW" > "$R/clock"; }
echo 0 > "$R/clock"
getprop() { echo "${BOOT_COMPLETE:-1}"; }
user_unlocked() { return 0; }
user_unlocked
package_status() { echo present; }
cleanup() { return 0; }
ip() { echo 'default via 192.0.2.1 dev wlan0 table 1001'; }
ip >/dev/null
manager_authorization() { echo granted; }
printf 1 > "$R/config/root-tun-enabled"
printf 1 > "$R/config/autostart-enabled"
write_settings
printf config > "$R/config/config.yaml"
printf '#!/bin/sh\nexit 0\n' > "$CORE"
chmod +x "$CORE"
cat > "$R/scripts/runtime.sh" <<'START'
#!/bin/sh
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
ip() { return 0; }
if bootstrap; then exit 1; fi
unlock boot
[ "$FAKE_NOW" -eq 170 ]
echo 'PASS dependency wait has 50 second budget'
