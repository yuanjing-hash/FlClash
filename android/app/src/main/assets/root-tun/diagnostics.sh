#!/system/bin/sh
R=/data/adb/flclash-root
exec 2>&1

collect() {
    printf '\n[%s]\n' "$1"
    shift
    "$@"
    printf '\nexit=%s\n' "$?"
}

printf '\n[FLCLASH:device:BEGIN]\n'
for property in ro.build.version.release ro.build.version.sdk ro.build.version.incremental ro.build.version.security_patch; do
    collect "$property" getprop "$property"
done
collect 'uname -a' uname -a
collect PAGE_SIZE getconf PAGE_SIZE
collect 'ksud -V' ksud -V
collect '/data/adb/ksud -V' /data/adb/ksud -V
collect '/data/adb/ksu/ksud -V' /data/adb/ksu/ksud -V
collect 'KernelSU properties' sh -c 'getprop | grep -i -E "kernelsu|ksu\\."'
collect 'dmesg AVC (last 200)' sh -c 'dmesg | grep -i avc | tail -n 200'
collect 'logcat AVC (last 200)' sh -c 'logcat -b events -b main -d -t 2000 | grep -i avc | tail -n 200'
printf '\n[FLCLASH:device:END]\n'
if [ -f "$R/logs/restore-diff.txt" ]; then
    printf '\n[FLCLASH:restore-diff:BEGIN]\n'
    cat "$R/logs/restore-diff.txt"
    printf '\n[FLCLASH:restore-diff:END]\n'
fi
printf '\n[FLCLASH:network:BEGIN]\n'
collect SELinux getenforce
for family in -4 -6; do
    collect "$family rules" ip "$family" rule show
    collect "$family routes" ip "$family" route show table all
done
collect Links ip link show
collect Addresses ip addr show
collect iptables iptables-save
collect ip6tables ip6tables-save
collect 'VPN connectivity' sh -c 'dumpsys connectivity | grep -i -E "vpn|TRANSPORT_VPN|lockdown"'
collect 'Root state' sh -c 'cat /data/adb/flclash-root/state/status /data/adb/flclash-root/state/private-dns /data/adb/flclash-root/state/auth-status /data/adb/flclash-root/state/owned.boot /data/adb/flclash-root/run/*.pid /data/adb/flclash-root/run/*.heartbeat /data/adb/flclash-root/run/generation /data/adb/flclash-root/run/boot-id'
for name in core.log core.log.1 validation.log watchdog.log watchdog.log.1 supervisor.log supervisor.log.1 transitions.log boot.log boot.log.1; do
    collect "$name" tail -c 131072 "$R/logs/$name"
done
collect Baseline sh -c 'cat /data/adb/flclash-root/state/baseline.*'
printf '\n[FLCLASH:network:END]\n'
