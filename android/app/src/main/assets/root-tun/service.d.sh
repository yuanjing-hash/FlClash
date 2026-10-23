#!/system/bin/sh
# flclash-root service.d v1
umask 077
R=/data/adb/flclash-root
[ ! -L "$R" ] && [ -d "$R/logs" ] && [ ! -L "$R/logs" ] || exit 0
[ "$(stat -c %u "$R")" = 0 ] || exit 0
(
    boot_id=$(cat /proc/sys/kernel/random/boot_id) || exit 1
    mkdir "$R/run/boot-$boot_id" 2>/dev/null || exit 0
    while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
    [ "$(cat "$R/config/root-tun-enabled" 2>/dev/null)" = 1 ] || exit 0
    [ "$(cat "$R/config/autostart-enabled" 2>/dev/null)" = 1 ] || exit 0
    if [ ! -L "$R/scripts/runtime.sh" ] && [ -s "$R/config/config.yaml" ] && [ -x "$R/bin/mihomo" ]; then
        /system/bin/sh "$R/scripts/runtime.sh" start || printf '%s AUTOSTART_FAILED\n' "$(date +%s)"
    else
        printf '%s AUTOSTART_FAILED missing runtime or config\n' "$(date +%s)"
    fi
) </dev/null >> "$R/logs/boot.log" 2>&1 &
