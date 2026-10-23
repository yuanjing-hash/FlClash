#!/system/bin/sh
set -u

base=/data/adb/flclash-root
run_id=${1:?run id required}
test_ip=${2:?test IPv4 required}
test_host=${3:?test host required}
case "$run_id" in ''|*[!A-Za-z0-9._-]*) exit 1 ;; esac
run=$base/runs/$run_id
secret=root-tun-b-spike
passes=0
failures=0
pid=
birth=
owned_rules=0
mkdir -p "$run" || exit 1
cd "$base" || exit 1
export TMPDIR="$base"

check() {
    check_label=$1
    shift
    if "$@"; then
        printf 'PASS %s\n' "$check_label"
        passes=$((passes + 1))
        return 0
    fi
    printf 'FAIL %s\n' "$check_label"
    failures=$((failures + 1))
    return 1
}

alive() {
    [ -n "$pid" ] && [ -r "/proc/$pid/stat" ] &&
        [ "$(awk '{print $22}' "/proc/$pid/stat")" = "$birth" ] &&
        [ "$(readlink "/proc/$pid/exe")" = "$base/mihomo" ]
}

stop_core() {
    signal=$1
    if alive; then
        kill -s "$signal" "$pid" || return 1
        attempt=0
        while alive && [ "$attempt" -lt 15 ]; do
            sleep 1
            attempt=$((attempt + 1))
        done
        alive && return 1
    fi
    if [ -n "$pid" ]; then
        wait "$pid" 2>/dev/null || true
        rm -f "$base/mihomo.pid"
    fi
    pid=
}

cleanup_rules() {
    [ "$owned_rules" -eq 1 ] || return 0
    alive && return 1
    for family in -4 -6; do
        priority=9000
        while [ "$priority" -le 9010 ]; do
            count=0
            while ip "$family" rule show | awk -v p="$priority:" '$1 == p {found=1} END {exit !found}'; do
                [ "$count" -lt 32 ] || return 1
                ip "$family" rule del pref "$priority" || return 1
                count=$((count + 1))
            done
            priority=$((priority + 1))
        done
    done
}

finish() {
    stop_core TERM || stop_core KILL || true
    cleanup_rules || true
    printf 'SUMMARY PASS=%s FAIL=%s\n' "$passes" "$failures" > "$run/summary"
    cat "$run/summary"
    rmdir "$base/.spike-lock" 2>/dev/null || true
}
trap 'finish' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM

capture() {
    destination=$1
    shift
    if "$@" > "$destination" 2>&1; then
        printf '0\n' > "$destination.status"
    else
        printf '%s\n' "$?" > "$destination.status"
        return 1
    fi
}

snapshot() {
    directory=$run/$1
    mkdir -p "$directory" || return 1
    result=0
    capture "$directory/rules4" ip rule || result=1
    capture "$directory/rules6" ip -6 rule || result=1
    capture "$directory/routes4" ip route show table all || result=1
    capture "$directory/routes6" ip -6 route show table all || result=1
    capture "$directory/iptables" iptables-save || result=1
    capture "$directory/ip6tables" ip6tables-save || result=1
    capture "$directory/link" ip link || result=1
    for name in rules4 rules6 routes4 routes6 iptables ip6tables link; do
        sed -e '/^#/d' -e 's/\[[0-9][0-9]*:[0-9][0-9]*\]/[0:0]/g' \
            -e 's/expires [0-9][0-9]*sec/expires DYNAMIC/g' \
            "$directory/$name" > "$directory/$name.normalized" || result=1
    done
    return "$result"
}

restored() {
    phase=$1
    result=0
    for name in rules4 rules6 routes4 routes6 iptables ip6tables link; do
        if [ "$(cat "$run/$phase/$name.status")" != 0 ] ||
            ! cmp -s "$run/before/$name.normalized" "$run/$phase/$name.normalized"; then
            printf 'Changed/unreadable: %s/%s\n' "$phase" "$name"
            result=1
        fi
    done
    return "$result"
}

no_vpn() {
    capture "$run/$1-connectivity" dumpsys connectivity || return 1
    [ -s "$run/$1-connectivity" ] &&
        ! grep -E 'TRANSPORT_VPN|Transports:.*VPN|type: VPN' "$run/$1-connectivity"
}

selinux_capture() {
    prefix=$1
    capture "$run/$prefix-getenforce" getenforce || return 1
    capture "$run/$prefix-dmesg" dmesg || return 1
    capture "$run/$prefix-logcat" logcat -b all -d -v epoch -t 2000
}

no_new_avc() {
    : > "$run/avc-new.log"
    for source in dmesg logcat; do
        awk 'FILENAME==ARGV[1] {seen[$0]=1; next} /avc: *denied/ && !seen[$0]' \
            "$run/before-$source" "$run/after-$source" >> "$run/avc-new.log" || return 1
    done
    cat "$run/avc-new.log"
    [ ! -s "$run/avc-new.log" ]
}

reserved_free() {
    ! awk '$1+0 >= 9000 && $1+0 <= 9010 {found=1} END {exit !found}' \
        "$run/before/rules4" "$run/before/rules6" || return 1
    for family in -4 -6; do
        routes=$(ip "$family" route show table 20220 2>&1)
        rc=$?
        if [ "$rc" -ne 0 ]; then
            printf '%s\n' "$routes" | grep -E 'FIB table does not exist|No such file' >/dev/null || return 1
        elif [ -n "$routes" ]; then
            printf '%s\n' "$routes"
            return 1
        fi
    done
    ! ip link show dev FlRootB >/dev/null 2>&1
}

fixed_config() {
    grep -qx '  device: FlRootB' config.yaml &&
        grep -qx '  auto-route: true' config.yaml &&
        grep -qx '  auto-detect-interface: true' config.yaml &&
        grep -Fxq '  exclude-uid: [0]' config.yaml &&
        grep -qx '  iproute2-table-index: 20220' config.yaml &&
        grep -qx '  iproute2-rule-index: 9000' config.yaml &&
        grep -qx '  auto-redirect: false' config.yaml &&
        grep -qx 'external-controller: 127.0.0.1:19090' config.yaml &&
        grep -qx "secret: $secret" config.yaml
}

start_core() {
    phase=$1
    nohup "$base/mihomo" -d "$base" -f "$base/config.yaml" \
        > "$run/core-$phase.log" 2>&1 < /dev/null &
    pid=$!
    birth=$(awk '{print $22}' "/proc/$pid/stat")
    printf '%s %s\n' "$pid" "$birth" > "$base/mihomo.pid"
    attempt=0
    while [ "$attempt" -lt 20 ]; do
        if alive && "$base/probe" health "$secret"; then
            grep -E '^Uid:[[:space:]]+0[[:space:]]+0' "/proc/$pid/status"
            return $?
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

tun_up() {
    ip link show dev FlRootB > "$run/tun-link" 2>&1 &&
        grep -E '<([^>]*,)?UP(,|>)' "$run/tun-link"
}

printf 'Device root: '; id
printf 'su version: '; su -v 2>&1 || true
if command -v magisk >/dev/null 2>&1; then
    printf 'Root scheme: Magisk '; magisk -v
elif [ -d /data/adb/ksu ]; then
    printf 'Root scheme: KernelSU (directory evidence)\n'
elif [ -d /data/adb/ap ]; then
    printf 'Root scheme: APatch (directory evidence)\n'
else
    printf 'Root scheme: UNKNOWN; verify su implementation manually\n'
fi
printf 'Private DNS: '; settings get global private_dns_mode
settings get global private_dns_specifier
for utility in ip iptables-save ip6tables-save cmp awk sed grep readlink nohup; do
    check "utility_$utility" command -v "$utility" || exit 1
done
check root test "$(id -u)" = 0 || exit 1
check fixed_config fixed_config || exit 1
check baseline_snapshot snapshot before || exit 1
check reserved_priorities_table_link reserved_free || exit 1
check baseline_no_VPN no_vpn before || exit 1
check baseline_selinux_visibility selinux_capture before || exit 1
check SELinux_enforcing grep -qx Enforcing "$run/before-getenforce" || true
owned_rules=1
check config_parse "$base/mihomo" -t -d "$base" -f "$base/config.yaml" || exit 1
check root_standalone_start start_core normal || exit 1
check TUN_UP tun_up || true
check no_TRANSPORT_VPN no_vpn running || true
check running_snapshot snapshot running || true
check nonroot_HTTP_TUN_and_controller "$base/probe" --shell traffic "$test_ip" "$test_host" "$secret" || true
check DNS_UDP_53_hijack "$base/probe" --shell dns udp || true
check DNS_TCP_53_hijack "$base/probe" --shell dns tcp || true
check normal_SIGTERM stop_core TERM || exit 1
check term_snapshot snapshot term || true
check normal_restore restored term || true
check crash_test_start start_core crash || exit 1
check crash_TUN_UP tun_up || exit 1
check crash_running_snapshot snapshot crash-running || true
check SIGKILL stop_core KILL || exit 1
check crash_snapshot snapshot crash || true
check SIGKILL_restore restored crash || true
check owned_residual_cleanup cleanup_rules || true
check recovered_snapshot snapshot recovered || true
check cleanup_restore restored recovered || true
check after_selinux_visibility selinux_capture after || true
check SELinux_still_enforcing grep -qx Enforcing "$run/after-getenforce" || true
check no_new_AVC no_new_avc || true
[ "$failures" -eq 0 ]
