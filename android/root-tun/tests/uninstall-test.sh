#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=$TESTS/../../app/src/main/assets/root-tun/runtime.sh
WORK=$(mktemp -d)
watchdog_pid=''
finish() {
    if [ -n "$watchdog_pid" ]; then kill "$watchdog_pid" 2>/dev/null || true; wait "$watchdog_pid" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap finish EXIT
export FAKE_NET="$WORK/net"
export PATH="$WORK/bin:$PATH"
mkdir -p "$FAKE_NET" "$WORK/bin" "$WORK/data" "$WORK/service.d"
for stub in pm log ip iptables ip6tables iptables-save ip6tables-save settings; do
    ln -s "$TESTS/network-stub.sh" "$WORK/bin/$stub"
done
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" \
    -e '/^export PATH=/d' -e '/^safe_tree || exit 1/,$d' \
    -e "s|/data/data/com.follow.clash.root|$WORK/data/com.follow.clash.root|g" \
    -e "s|/data/adb/service.d|$WORK/service.d|g" "$SOURCE" > "$WORK/functions.sh"
# shellcheck source=/dev/null
. "$WORK/functions.sh"
mkdir -p "$STATE" "$RUN" "$R/logs"
IDENTITY="$$ $(ticks "$$") $BOOT"
export IDENTITY
[ "$(package_status)" = present ]
echo prefix > "$FAKE_NET/package"
[ "$(package_status)" = absent ]
echo 'PASS exact root package; similarly named package does not count'
for result in fail timeout; do
    echo "$result" > "$FAKE_NET/package"
    [ "$(package_status)" = unknown ]
done
echo 'PASS pm errors and timeouts remain unknown'
echo android-absent > "$FAKE_NET/package"
[ "$(package_status)" = absent ]
echo binder-failure > "$FAKE_NET/package"
[ "$(package_status)" = unknown ]
echo 'PASS Android pm path exit 1 requires a successful exact list query; binder failure remains unknown'
echo absent > "$FAKE_NET/package"
mkdir "$WORK/data/com.follow.clash.root"
[ "$(package_status)" = present ]
rmdir "$WORK/data/com.follow.clash.root"
echo 'PASS retained data from uninstall -k prevents deletion'
missing_count=0
if check_uninstall; then exit 1; fi
[ -d "$R" ]
echo fail > "$FAKE_NET/package"
if check_uninstall; then exit 1; fi
[ "$missing_count" -eq 0 ]
echo absent > "$FAKE_NET/package"
if check_uninstall; then exit 1; fi
printf '%s\n' '#!/system/bin/sh' '# flclash-root service.d v1' > "$WORK/service.d/flclash-root.sh"
printf foreign > "$WORK/service.d/foreign.sh"
mkdir "$RUN/owner.lock"
printf '999999 1 previous-boot\n' > "$RUN/supervisor.pid"
check_uninstall
[ ! -e "$R" ] && [ ! -e "$WORK/service.d/flclash-root.sh" ]
[ -f "$WORK/service.d/foreign.sh" ]
grep -q 'cleanup complete' "$FAKE_NET/logcat"
echo 'PASS two consecutive absences clean runtime and only owned entry; logcat retains evidence'
mkdir -p "$STATE" "$RUN" "$R/logs" "$R/config"
echo 1 > "$R/config/root-tun-enabled"
echo 0 > "$R/config/autostart-enabled"
echo present > "$FAKE_NET/package"
cat > "$WORK/watchdog.sh" <<WATCHDOG
#!/bin/sh
. "$WORK/functions.sh"
IDENTITY="\$\$ \$(ticks "\$\$") \$BOOT"
start_probe() {
    case "\$1" in
        package) record_package_status "\$(package_status)" && exit 0 ;;
    esac
    return 0
}
watchdog
WATCHDOG
detach() { sh "$WORK/watchdog.sh" & watchdog_pid=$!; }
stop_runtime
[ "$(cat "$STATE/status")" = 'disabled -' ]
[ "$(cat "$R/config/autostart-enabled")" = 0 ]
echo absent > "$FAKE_NET/package"
for _attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    [ -d "$R" ] || break
    sleep 1
done
[ ! -e "$R" ]
wait "$watchdog_pid"
watchdog_pid=''
echo 'PASS uninstall after proxyStop with autostart disabled removes runtime'
