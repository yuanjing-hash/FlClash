#!/system/bin/sh
set -u
PROC=/proc
LOG_ROOTS='/data/misc/update_engine_log /data/misc/update_engine /cache/recovery'
seen=''
attempts=0
sources=0

read_log() {
    [ "$attempts" -lt 5 ] && [ -f "$1" ] || return 0
    identity=${2:-$(readlink -f "$1" 2>/dev/null)}
    [ -n "$identity" ] || identity=$1
    case "$identity" in *.gz|*.zip|*.bin) return 0 ;; esac
    if printf '%s' "$seen" | grep -Fx -- "$identity" >/dev/null; then return 0; fi
    seen="$seen$identity
"
    attempts=$((attempts + 1))
    printf '\n[ota-log:%s]\n' "$identity"
    if ! tail -c 524288 "$1" > "$D/ota-source.$attempts"; then
        echo source-read-failed
        return 0
    fi
    sources=$((sources + 1))
    grep -i -E -B2 -A3 'timestamp|kPayload|ErrorCode|error|verification|verify|partition.*version|post-timestamp|pre-timestamp' \
        "$D/ota-source.$attempts" | tail -n 80 | head -c 12288
    printf '\n[ota-log-tail]\n'
    tail -c 2048 "$D/ota-source.$attempts"
    echo
}

for pid in $(pidof update_engine update_engine_sideload 2>/dev/null); do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    executable=$(tr '\000' '\n' < "$PROC/$pid/cmdline" 2>/dev/null | head -n 1)
    case "${executable##*/}" in update_engine|update_engine_sideload) ;; *) continue ;; esac
    printf '\n[ota-process:%s %s]\n' "$pid" "$executable"
    for fd in "$PROC/$pid"/fd/*; do
        target=$(readlink "$fd" 2>/dev/null) || continue
        case "$target" in
            *update_engine*log*|*log*update_engine*|*/update_engine.[0-9]*|*/last_log|*/last_install) read_log "$fd" "$target" ;;
        esac
    done
done

for directory in $LOG_ROOTS; do
    printf '\n[ota-directory:%s]\n' "$directory"
    if [ ! -d "$directory" ]; then echo directory-unavailable; continue; fi
    for path in $(ls -1t "$directory"/update_engine* "$directory"/last_log "$directory"/last_install "$directory"/log 2>/dev/null | head -n 3); do
        read_log "$path"
    done
done

printf '\n[ota-logcat]\n'
logcat -b all -d -v threadtime -t 12000 2>&1 |
    grep -i -E 'update_engine|updateengine|updater|system.?update|recoverysystem|kPayload|timestamp.*(invalid|fail|error)|时间戳.*(失败|错误)|ota.*(timestamp|verif|error|fail)' |
    tail -n 160 | { head -c 24576 > "$D/ota-logcat.txt"; cat > /dev/null; }
if [ -s "$D/ota-logcat.txt" ]; then
    cat "$D/ota-logcat.txt"
    sources=$((sources + 1))
fi
printf '\nota-sources=%s\n' "$sources"
if [ "$sources" -eq 0 ]; then echo 'NO_OTA_LOG_SOURCES: no readable updater evidence was collected'; exit 3; fi
