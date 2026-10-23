#!/system/bin/sh
set -u
umask 077
R=/data/adb/flclash-root
export TMPDIR=$R/tmp
export PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin
CORE=$R/bin/mihomo
STATE=$R/state
RUN=$R/run

safe_tree() {
    [ ! -L "$R" ] || return 1
    [ -d "$R" ] || return 1
    [ "$(stat -c %u "$R")" = 0 ] || return 1
    [ -z "$(find "$R" -type l -print)" ] || return 1
}

ticks() {
    # Remove comm first: its spaces and parentheses are not stat field separators.
    sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
}

alive() {
    [ -f "$1" ] || return 1
    read -r recorded_pid recorded_ticks recorded_boot < "$1"
    [ "$recorded_boot" = "$(cat /proc/sys/kernel/random/boot_id)" ] || return 1
    case "$recorded_pid:$recorded_ticks" in *[!0-9:]*|:|*:) return 1 ;; esac
    [ "$recorded_pid" -gt 1 ] && [ "$(ticks "$recorded_pid")" = "$recorded_ticks" ]
}

publish() {
    printf '%s %s\n' "$1" "${2:--}" > "$STATE/status.tmp"
    mv "$STATE/status.tmp" "$STATE/status"
    printf '%s %s %s\n' "$(date +%s)" "$1" "${2:--}" >> "$R/logs/transitions.log"
}

vacant() {
    for family in -4 -6; do
        rules=$(ip "$family" rule show) || return 1
        [ -z "$(printf '%s\n' "$rules" | awk -F: '$1 >= 8990 && $1 <= 9011')" ] || return 1
        if ! routes=$(ip "$family" route show table 2022 2>&1); then
            case "$routes" in
                *'does not exist'*|*'No such file'*) routes='' ;;
                *) return 1 ;;
            esac
        fi
        [ -z "$routes" ] || return 1
    done
    links=$(ip link show) || return 1
    if printf '%s\n' "$links" | grep -E '^[0-9]+: flcrtun0[:@]' >/dev/null; then return 1; fi
    for tool in iptables ip6tables; do
        chains=$("$tool" -w 1 -S) || return 1
        if printf '%s\n' "$chains" | grep -E '^(-N FCR_OUTPUT$|-A FCR_OUTPUT )' >/dev/null; then return 1; fi
    done
    return 0
}

baseline() {
    for family in -4 -6; do
        ip "$family" rule show > "$STATE/baseline.$family.rules" || return 1
        ip "$family" route show table all > "$STATE/baseline.$family.routes" || return 1
    done
    ip link show > "$STATE/baseline.links" || return 1
    ip addr show > "$STATE/baseline.addr" || return 1
    iptables-save > "$STATE/baseline.iptables" || return 1
    ip6tables-save > "$STATE/baseline.ip6tables" || return 1
}

install_rules() {
    vacant || return 1
    baseline || return 1
    # The reservation is written before any network mutation; rollback only touches this namespace.
    printf '%s\n' 'rules:8990-9011 table:2022 link:flcrtun0 chains:FCR_OUTPUT' > "$STATE/owned"
    sync
    ip -4 rule add pref 8990 fwmark 0x40000000/0x40000000 goto 9011 || return 1
    ip -4 rule add pref 8991 iif lo lookup 2022 || return 1
    iptables -w 1 -N FCR_OUTPUT || return 1
    iptables -w 1 -A FCR_OUTPUT -o lo -j RETURN || return 1
    iptables -w 1 -A FCR_OUTPUT -m mark --mark 0x40000000/0x40000000 -j RETURN || return 1
    for protocol in udp tcp; do
        iptables -w 1 -A FCR_OUTPUT ! -o flcrtun0 -p "$protocol" --dport 53 -j REJECT || return 1
    done
    iptables -w 1 -I OUTPUT 1 -j FCR_OUTPUT || return 1
    ip6tables -w 1 -N FCR_OUTPUT || return 1
    ip6tables -w 1 -A FCR_OUTPUT -o lo -j RETURN || return 1
    for icmp_type in 133 134 135 136; do
        ip6tables -w 1 -A FCR_OUTPUT -p ipv6-icmp --icmpv6-type "$icmp_type" -j RETURN || return 1
    done
    ip6tables -w 1 -A FCR_OUTPUT -j REJECT || return 1
    ip6tables -w 1 -I OUTPUT 1 -j FCR_OUTPUT || return 1
    update_private_dns
}

update_private_dns() {
    private_dns=$(settings get global private_dns_mode 2>/dev/null)
    if [ "$private_dns" = null ] || [ -z "$private_dns" ]; then
        private_dns=$(settings get global private_dns_default_mode 2>/dev/null)
        [ "$private_dns" != null ] && [ -n "$private_dns" ] || private_dns=opportunistic
    fi
    [ "$private_dns" != "${last_private_dns:-unset}" ] || return 0
    for protocol in udp tcp; do
        while iptables -w 1 -C FCR_OUTPUT -p "$protocol" --dport 853 -j REJECT 2>/dev/null; do
            iptables -w 1 -D FCR_OUTPUT -p "$protocol" --dport 853 -j REJECT || return 1
        done
        if [ "$private_dns" = opportunistic ]; then
            iptables -w 1 -A FCR_OUTPUT -p "$protocol" --dport 853 -j REJECT || return 1
        fi
    done
    last_private_dns=$private_dns
    printf '%s\n' "$private_dns" > "$STATE/private-dns"
}

stop_core() {
    if alive "$RUN/core.pid"; then
        kill -TERM "$recorded_pid" || return 1
        for _wait_count in 1 2 3 4 5 6 7 8 9 10; do
            alive "$RUN/core.pid" || break
            sleep 0.1
        done
        if alive "$RUN/core.pid"; then kill -KILL "$recorded_pid" || return 1; fi
    fi
    rm -f "$RUN/core.pid"
}

cleanup() {
    stop_core || return 1
    if [ ! -f "$STATE/owned" ]; then
        vacant
        return $?
    fi
    cleanup_ok=1
    for tool in iptables ip6tables; do
        while "$tool" -w 1 -C OUTPUT -j FCR_OUTPUT 2>/dev/null; do
            "$tool" -w 1 -D OUTPUT -j FCR_OUTPUT || { cleanup_ok=0; break; }
        done
        if "$tool" -w 1 -S FCR_OUTPUT >/dev/null 2>&1; then
            "$tool" -w 1 -F FCR_OUTPUT || cleanup_ok=0
            "$tool" -w 1 -X FCR_OUTPUT || cleanup_ok=0
        fi
    done
    for family in -4 -6; do
        priority=8990
        while [ "$priority" -le 9011 ]; do
            while ip "$family" rule show | awk -F: -v p="$priority" '$1 == p {found=1} END {exit !found}'; do
                ip "$family" rule del pref "$priority" || { cleanup_ok=0; break; }
            done
            priority=$((priority + 1))
        done
        ip "$family" route flush table 2022 2>/dev/null || true
    done
    if ip link show flcrtun0 >/dev/null 2>&1; then ip link delete flcrtun0 || cleanup_ok=0; fi
    vacant || cleanup_ok=0
    [ "$cleanup_ok" -eq 1 ] || return 1
    rm -f "$STATE/owned"
}

launch_core() {
    if [ -f "$R/logs/core.log" ] && [ "$(stat -c %s "$R/logs/core.log")" -gt 1048576 ]; then
        mv "$R/logs/core.log" "$R/logs/core.log.1"
    fi
    "$CORE" -d "$R/config" -f "$R/config/config.yaml" >> "$R/logs/core.log" 2>&1 &
    core_pid=$!
    core_ticks=$(ticks "$core_pid")
    [ -n "$core_ticks" ] || return 1
    printf '%s %s %s\n' "$core_pid" "$core_ticks" "$(cat /proc/sys/kernel/random/boot_id)" > "$RUN/core.pid"
}

boot_seconds() {
    cut -d. -f1 /proc/uptime
}

supervise() {
    if ! mkdir "$RUN/owner.lock" 2>/dev/null; then
        alive "$RUN/supervisor.pid" && return 1
        rmdir "$RUN/owner.lock" || return 1
        mkdir "$RUN/owner.lock" || return 1
    fi
    printf '%s %s %s\n' "$$" "$(ticks "$$")" "$(cat /proc/sys/kernel/random/boot_id)" > "$RUN/supervisor.pid"
    trap 'touch "$RUN/stop"' TERM INT HUP
    rm -f "$RUN/stop" "$RUN/healthy"
    publish starting
    if [ ! -c /dev/net/tun ]; then
        publish failed TUN_DEVICE_UNSUPPORTED
    elif ! install_rules; then
        publish stopping NETWORK_RULES_APPLY_FAILED
        if cleanup; then publish failed NETWORK_RULES_APPLY_FAILED; else publish stopping CLEANUP_FAILED; fi
    elif ! launch_core; then
        if cleanup; then publish failed CORE_START_FAILED; else publish stopping CLEANUP_FAILED; fi
    else
        deadline=$(($(boot_seconds) + 9))
        crash_times=''
        final_code=''
        while [ ! -f "$RUN/stop" ]; do
            now=$(boot_seconds)
            if ! alive "$RUN/core.pid"; then
                case "$(cat "$STATE/status")" in
                    starting*)
                        if tail -n 30 "$R/logs/core.log" | grep -i -E '(tun.*(error|fail)|error.*tun)' >/dev/null; then
                            final_code=TUN_CREATE_FAILED
                        else final_code=CORE_START_FAILED; fi
                        break
                        ;;
                esac
                retained=''
                crash_count=1
                for crash_time in $crash_times; do
                    if [ $((now - crash_time)) -lt 300 ]; then
                        retained="$retained $crash_time"
                        crash_count=$((crash_count + 1))
                    fi
                done
                crash_times="$retained $now"
                [ "$crash_count" -lt 3 ] || { final_code=CORE_CRASH_LOOP; break; }
                publish recovering CORE_CRASHED_RECOVERING
                rm -f "$RUN/healthy"
                recovery_deadline=${recovery_deadline:-$((now + 26))}
                stop_core
                # TUN death removes its routes, but sing-tun leaves policy rules after SIGKILL.
                if ! cleanup || ! install_rules || ! launch_core; then final_code=CORE_RECOVERY_FAILED; break; fi
                deadline=$recovery_deadline
            fi
            rm -f "$RUN/healthy"
            if alive "$RUN/core.pid" && ip link show flcrtun0 2>/dev/null | grep -q UP; then
                port=$(cat "$R/config/controller.port")
                if nc -w 1 127.0.0.1 "$port" < "$R/config/health.http" 2>/dev/null | head -n 1 | grep -q ' 200 '; then
                    touch "$RUN/healthy"
                else
                    rm -f "$RUN/healthy"
                fi
            fi
            if [ -f "$RUN/healthy" ]; then
                current=$(cat "$STATE/status")
                case "$current" in
                    recovering*) publish running CORE_RECOVERED; unset recovery_deadline ;;
                    starting*) publish running ;;
                esac
                deadline=$((now + 26))
                if ! ip -4 route show table 2022 | grep -q flcrtun0 ||
                    ! iptables -w 1 -C OUTPUT -j FCR_OUTPUT || ! ip6tables -w 1 -C OUTPUT -j FCR_OUTPUT; then
                    final_code=NETWORK_RULES_APPLY_FAILED
                    break
                fi
            elif [ "$now" -ge "$deadline" ]; then
                case "$(cat "$STATE/status")" in
                    recovering*) final_code=CORE_RECOVERY_FAILED ;;
                    *) final_code=START_TIMEOUT ;;
                esac
                break
            fi
            update_private_dns || { final_code=DNS_TAKEOVER_FAILED; break; }
            sleep 1
        done
        publish stopping "${final_code:--}"
        if cleanup; then
            if [ -n "$final_code" ]; then publish failed "$final_code"; else publish disabled; fi
        else
            publish stopping CLEANUP_FAILED
        fi
    fi
    while [ -f "$STATE/owned" ]; do
        publish stopping CLEANUP_FAILED
        sleep 1
        if cleanup; then publish failed CLEANUP_FAILED; fi
    done
    rm -f "$RUN/supervisor.pid" "$RUN/healthy"
    rmdir "$RUN/owner.lock"
}

safe_tree || exit 1
case "${1:-}" in
    start)
        alive "$RUN/supervisor.pid" && exit 0
        nohup /system/bin/sh "$R/scripts/runtime.sh" supervise </dev/null >> "$R/logs/watchdog.log" 2>&1 &
        ;;
    supervise) supervise ;;
    stop|cleanup)
        if alive "$RUN/supervisor.pid"; then
            touch "$RUN/stop"
            for _wait_count in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27; do
                alive "$RUN/supervisor.pid" || break
                sleep 0.1
            done
            alive "$RUN/supervisor.pid" && exit 1
        fi
        cleanup || { publish stopping CLEANUP_FAILED; exit 1; }
        publish disabled
        ;;
    status)
        cat "$STATE/status" 2>/dev/null || echo disabled
        printf 'dns:%s\n' "$(cat "$STATE/private-dns" 2>/dev/null)"
        always_on=$(settings get secure always_on_vpn_app 2>/dev/null)
        if [ "$always_on" = "$(cat "$R/config/app.package" 2>/dev/null)" ]; then echo always-on:yes; fi
        alive "$RUN/supervisor.pid" || exit 1
        alive "$RUN/core.pid" || exit 1
        ip link show flcrtun0 | grep -q 'UP' || exit 1
        ip -4 route show table 2022 | grep -q flcrtun0 || exit 1
        ;;
    healthy)
        alive "$RUN/core.pid" || exit 1
        touch "$RUN/healthy"
        ;;
    *) exit 64 ;;
esac
