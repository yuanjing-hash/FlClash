#!/bin/sh
set -u

base=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
remote=/data/adb/flclash-root
serial=${1:-${ANDROID_SERIAL:-}}
if [ -z "$serial" ] && command -v adb >/dev/null 2>&1; then
    serial=$(adb devices 2>/dev/null | awk 'NR > 1 && $2 == "device" {print $1}')
fi
stamp=$(date +%Y%m%d-%H%M%S)
label=$(printf '%s' "${serial:-no-device}" | tr -c 'A-Za-z0-9._-' '_')
run_id=$stamp-$label-$$
mkdir -p "$base/logs/$run_id" "$base/.cache" || exit 1
log=$base/logs/$run_id.log
local_run=$base/logs/$run_id

quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

root_cmd() {
    adb -s "$serial" shell -T "su -c $(quote "$1")"
}

upload() {
    root_cmd "umask 077; cat > $remote/.incoming-$2" < "$1" &&
        root_cmd "chmod $3 $remote/.incoming-$2 && mv $remote/.incoming-$2 $remote/$2"
}

host_main() {
    printf 'root TUN B: %s\n' "$run_id"
    for utility in adb tar diff tee; do
        command -v "$utility" >/dev/null 2>&1 || {
            printf 'FAIL prerequisite: missing %s\n' "$utility"
            return 1
        }
    done
    if [ -z "$serial" ]; then
        serial=$(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
    fi
    case "$serial" in
        ''|*[!A-Za-z0-9._:-]*)
            printf 'FAIL device: specify exactly one authorized device serial\n'
            return 1 ;;
    esac
    [ "$(adb -s "$serial" get-state)" = device ] || return 1
    printf 'Device: %s\n' "$serial"
    adb -s "$serial" shell 'getprop ro.product.model; getprop ro.build.version.release; command -v su' || return 1
    sdk=$(adb -s "$serial" shell getprop ro.build.version.sdk | tr -d '\r')
    abi=$(adb -s "$serial" shell getprop ro.product.cpu.abi | tr -d '\r')
    case "$sdk" in ''|*[!0-9]*) return 1 ;; esac
    [ "$sdk" -ge 29 ] || { printf 'FAIL Android: API %s < 29\n' "$sdk"; return 1; }
    case "$abi" in
        arm64-v8a) arch=arm64 ;;
        x86_64) arch=x86_64 ;;
        *) printf 'FAIL ABI: %s\n' "$abi"; return 1 ;;
    esac
    for artifact in mihomo probe; do
        [ -f "$base/bin/$arch/$artifact" ] || {
            printf 'FAIL binary: run sh %s/build.sh first\n' "$base"
            return 1
        }
    done
    root_uid=$(root_cmd 'id -u' | tr -d '\r')
    [ "$root_uid" = 0 ] || { printf 'FAIL su root: %s\n' "$root_uid"; return 1; }
    root_cmd "umask 077; mkdir -p $remote; chmod 700 $remote; test ! -e $remote/mihomo.pid && mkdir $remote/.spike-lock" || {
        printf 'FAIL ownership: existing pid/lock; inspect the previous run before retrying\n'
        return 1
    }
    locked=1
    upload "$base/bin/$arch/mihomo" mihomo 500 &&
        upload "$base/bin/$arch/probe" probe 500 &&
        upload "$base/config.yaml" config.yaml 600 &&
        upload "$base/device-spike.sh" device-spike.sh 500 || return 1
    test_ip=${SPIKE_TEST_IP:-1.1.1.1}
    test_host=${SPIKE_TEST_HOST:-one.one.one.one}
    case "$test_ip:$test_host" in *[!A-Za-z0-9.:-]*) printf 'FAIL test endpoint\n'; return 1 ;; esac
    locked=0
    root_cmd "sh $remote/device-spike.sh $run_id $test_ip $test_host"
    device_status=$?
    if ! root_cmd "cd $remote/runs/$run_id && tar -cf - ." > "$local_run/results.tar" 2> "$local_run/pull.err"; then
        cat "$local_run/pull.err"
        return 1
    fi
    tar -xf "$local_run/results.tar" -C "$local_run" || return 1
    for phase in before running term crash-running crash recovered; do
        for snapshot in rules4 rules6 routes4 routes6 iptables ip6tables link; do
            file=$local_run/$phase/$snapshot
            if [ -f "$file" ]; then
                printf '\n--- %s/%s (raw) ---\n' "$phase" "$snapshot"
                cat "$file"
            fi
        done
    done
    for phase in term crash recovered; do
        for snapshot in rules4 rules6 routes4 routes6 iptables ip6tables link; do
            original=$local_run/before/$snapshot.normalized
            current=$local_run/$phase/$snapshot.normalized
            if [ -f "$original" ] && [ -f "$current" ]; then
                printf '\n--- diff before -> %s: %s ---\n' "$phase" "$snapshot"
                diff -u "$original" "$current" || true
            fi
        done
    done
    for file in "$local_run"/core-*.log "$local_run"/*-connectivity \
        "$local_run"/*-getenforce "$local_run"/*-dmesg "$local_run"/*-logcat \
        "$local_run"/avc-new.log "$local_run"/summary; do
        if [ -f "$file" ]; then
            printf '\n--- %s ---\n' "${file##*/}"
            cat "$file"
        fi
    done
    return "$device_status"
}

locked=0
finish() {
    if [ "$locked" -eq 1 ]; then
        root_cmd "rmdir $remote/.spike-lock" >/dev/null 2>&1 || true
        locked=0
    fi
}
trap 'finish' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM
fifo=$base/.cache/$run_id.fifo
mkfifo "$fifo" || exit 1
tee "$log" < "$fifo" &
logger_pid=$!
{
    host_main
    status=$?
    printf '\n%s host run (exit=%s); log: %s\n' "$( [ "$status" -eq 0 ] && printf PASS || printf FAIL )" "$status" "$log"
} > "$fifo" 2>&1
wait "$logger_pid" || status=1
rm -f "$fifo"
finish
exit "$status"
