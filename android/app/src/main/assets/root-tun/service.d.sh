#!/system/bin/sh
# flclash-root service.d v2
umask 077
R=/data/adb/flclash-root
ENTRY=/data/adb/service.d/flclash-root.sh
[ ! -L /data/adb/service.d ] && [ ! -L "$ENTRY" ] || exit 0
if [ ! -f "$R/scripts/runtime.sh" ]; then
    if grep -qx '# flclash-root service.d v[12]' "$ENTRY" 2>/dev/null; then rm -f "$ENTRY"; fi
    exit 0
fi
[ ! -L "$R" ] && [ ! -L "$R/scripts" ] && [ ! -L "$R/scripts/runtime.sh" ] || exit 0
[ "$(stat -c %u "$R")" = 0 ] || exit 0
nohup setsid /system/bin/sh "$R/scripts/runtime.sh" boot </dev/null >/dev/null 2>&1 &
