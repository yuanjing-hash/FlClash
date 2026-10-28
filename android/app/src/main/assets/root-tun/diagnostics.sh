#!/system/bin/sh
# shellcheck disable=SC2016
R=/data/adb/flclash-root
exec 2>&1
if [ "$(id -u)" = 0 ]; then
    umask 077
    mkdir -p "$R/tmp" && chmod 700 "$R/tmp" || exit 1
    export TMPDIR="$R/tmp"
fi
D=$(mktemp -d "${TMPDIR:-$R/tmp}/root-diagnostics.XXXXXX") || exit 1
trap 'rm -rf "$D"' EXIT
export R D
if [ -n "${AUTH_SOURCE:-}" ]; then printf '%s\n' "$AUTH_SOURCE" > "$D/authorization.sh"
else cp "$R/scripts/authorization.sh" "$D/authorization.sh"; fi
pids=''
pending_items=''
printf '\n[FLCLASH:network:BEGIN]\n'

collect() {
    item=$1
    seconds=$2
    shift 2
    (
        # Drain after the truncation sentinel so producers retain their exit status instead of SIGPIPE.
        (
            result=0
            timeout -s KILL "$seconds" "$@" 2>&1 || result=$?
            printf '%s\n' "$result" > "$D/$item.exit"
        ) | { head -c 98305 > "$D/$item.raw"; cat > /dev/null; }
        result=$(cat "$D/$item.exit")
        size=$(wc -c < "$D/$item.raw" | tr -d ' ')
        truncated=no
        [ "$size" -le 98304 ] || truncated=yes
        head -c 98304 "$D/$item.raw" > "$D/$item.txt"
        collection_status=success
        if [ "$result" -ne 0 ]; then collection_status=failed
        elif grep -Eq '^(am|path|list|evidence|file|version|ps|ps-Z)-exit=[1-9]|not found|Permission denied|No such file' "$D/$item.txt"; then collection_status=partial; fi
        printf '%s exit=%s timeout=%s truncated=%s bytes=%s status=%s\n' "$item" "$result" \
            "$(case "$result" in 124|137) echo yes ;; *) echo no ;; esac)" "$truncated" "$size" "$collection_status" > "$D/$item.manifest"
    ) &
    pids="$pids $!"
    pending_items="$pending_items $item"
}

batch() {
    for collector_pid in $pids; do wait "$collector_pid" || true; done
    pids=''
    for completed_item in $pending_items; do
        printf '\n[%s]\n' "$completed_item"
        cat "$D/$completed_item.txt"
        printf '\n[collected] '
        cat "$D/$completed_item.manifest"
    done
    pending_items=''
}

collect clock 1 sh -c 'date +%s; date; cat /proc/uptime /proc/sys/kernel/random/boot_id'
collect boot-state 3 sh -c 'a=$(cut -d" " -f1 /proc/uptime); timeout -s KILL 1 am get-started-user-state 0; echo am-exit=$? uptime-before=$a uptime-after=$(cut -d" " -f1 /proc/uptime); timeout -s KILL 1 cmd user is-user-unlocked 0; echo cmd-exit=$?; for p in sys.user.0.ce_available sys.boot_completed; do echo "$p=$(getprop "$p")"; done'
collect tools 3 sh -c 'id; cat /proc/self/attr/current; for c in timeout nc od sha256sum cksum setsid ln sleep diff sed awk; do printf "%s: " "$c"; command -v "$c" || echo MISSING; done; ls -l /system/bin/awk; timeout -s KILL 1 nc -w 1 127.0.0.1 1 </dev/null; echo nc-w-exit=$?; printf x | od -An -tu1; printf x | sha256sum; timeout -s KILL 1 setsid sh -c ":"; echo setsid-exit=$?; sleep 0.1 && echo sleep-frac-ok; echo x | sed -E "s/x+/y/"; printf "a\n" > "$D/a"; printf "b\n" > "$D/b"; ln "$D/a" "$D/link" && echo hardlink-ok; diff -u "$D/a" "$D/b"; echo diff-exit=$?'
collect boot-evidence 1 sh -c 'for f in boot.log boot.log.1 service-context.txt notification-last.txt allowlist-denied.txt; do echo "[$f]"; tail -c 16000 "$R/logs/$f"; echo file-exit=$?; done'
collect auth-data 2 sh -c '. "$D/authorization.sh"; authorization_evidence "${APP_UID:-}" "${ROOT_MANAGER:-}"; echo evidence-exit=$?; manager_authorization "${APP_UID:-}" "${ROOT_MANAGER:-}"'
collect package 3 sh -c 'timeout -s KILL 1 pm path com.follow.clash.root; echo path-exit=$?; timeout -s KILL 1 pm list packages com.follow.clash; echo list-exit=$?; ls -ld /data/data/com.follow.clash.root; timeout -s KILL 1 pm list packages | grep -i -E "kernelsu|ksunext|sukisu|apatch|magisk"'
batch
collect device 2 sh -c 'uname -a; getconf PAGE_SIZE; for p in ro.build.version.release ro.build.version.sdk ro.build.version.incremental ro.build.version.security_patch; do echo "$p=$(getprop "$p")"; done; getprop | grep -i -E "kernelsu|ksu\."; for c in ksud /data/adb/ksud /data/adb/ksu/ksud; do "$c" -V; echo version-exit=$?; done; command -v su; ls -l /system/bin/su'
collect grep 1 sh -c 'printf "a\n" | grep "x\|a"; echo bre=$?; printf "a\n" | grep -E "x|a"; echo ere=$?; ls -l /system/bin/grep; toybox --version'
collect processes 2 sh -c 'ps -A -o pid,ppid,user,etime,label,args; echo ps-exit=$?; ps -AZ; echo ps-Z-exit=$?; cat /proc/loadavg'
collect directories 2 sh -c 'ls -la /data/adb/service.d; head -n 2 /data/adb/service.d/flclash-root.sh; sha256sum /data/adb/service.d/flclash-root.sh; ls -laR "$R" | head -n 200; for f in settings.json root-tun-enabled autostart-enabled root.manager app.uid; do echo "[$f]"; cat "$R/config/$f"; echo file-exit=$?; done'
collect runtime-state 1 sh -c 'for f in "$R"/state/status "$R"/state/private-dns "$R"/state/auth-status "$R"/state/owned.boot "$R"/state/session "$R"/state/session-stop "$R"/state/revocation-code "$R"/state/revoked-since "$R"/run/*.pid "$R"/run/*.heartbeat "$R"/run/generation "$R"/run/boot-id "$R"/run/stop "$R"/run/crash-times "$R"/run/adopt-deadline; do echo "[$f]"; cat "$f"; echo file-exit=$?; done'
collect notifications 2 sh -c 'dumpsys notification | grep -i -B2 -A6 flclash-root | head -n 60'
batch
collect ipv4 2 sh -c 'ip -4 rule show; ip -4 route show table all; ip link show; ip addr show'
collect ipv6 2 sh -c 'ip -6 rule show; ip -6 route show table all'
collect iptables 2 iptables-save
collect ip6tables 2 ip6tables-save
collect nft 2 nft list ruleset
collect selinux 2 sh -c 'getenforce; dmesg | grep -i avc | tail -n 100; logcat -b events -b main -d -t 1000 | grep -i avc | tail -n 100; logcat -d -s FlClashRoot -t 200'
batch
collect connectivity 2 sh -c 'dumpsys connectivity | grep -i -E "vpn|TRANSPORT_VPN|lockdown"'
collect restore-diff 1 cat "$R/logs/restore-diff.txt"
collect baseline 1 sh -c 'cat "$R"/state/baseline.*'
collect logs 1 sh -c 'for f in transitions.log watchdog.log watchdog.log.1 supervisor.log supervisor.log.1 core.log core.log.1 validation.log; do echo "[$f]"; tail -c 10000 "$R/logs/$f"; echo file-exit=$?; done'
batch
printf '\n[FLCLASH:network:END]\n'
items='clock boot-state tools boot-evidence auth-data package device grep processes directories runtime-state notifications ipv4 ipv6 iptables ip6tables nft selinux connectivity restore-diff baseline logs'
printf '\n[FLCLASH:manifest:BEGIN]\n'
for item in $items; do
    cat "$D/$item.manifest" 2>/dev/null || printf '%s not-collected\n' "$item"
done
printf '\n[FLCLASH:manifest:END]\n'
printf '\n[FLCLASH:device:BEGIN]\n'
cat "$D/clock.txt" "$D/device.txt"
printf '\n[FLCLASH:device:END]\n'
printf '\n[FLCLASH:restore-diff:BEGIN]\n'
cat "$D/restore-diff.txt"
printf '\n[FLCLASH:restore-diff:END]\n'
