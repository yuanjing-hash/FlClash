#!/system/bin/sh
set -u
umask 077
R=/data/adb/flclash-root
export TMPDIR=$R/tmp
export PATH=/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin:/data/adb/ap/bin
CORE=$R/bin/mihomo
STATE=$R/state
RUN=$R/run
BOOT=$(cat /proc/sys/kernel/random/boot_id)

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
    [ "$recorded_boot" = "$BOOT" ] || return 1
    case "$recorded_pid:$recorded_ticks" in *[!0-9:]*|:|*:) return 1 ;; esac
    [ "$recorded_pid" -gt 1 ] && [ "$(ticks "$recorded_pid")" = "$recorded_ticks" ] &&
        [ "$(sed 's/.*) //' "/proc/$recorded_pid/stat" 2>/dev/null | cut -d' ' -f1)" != Z ]
}

boot_seconds() {
    cut -d. -f1 /proc/uptime
}

boot_ms() {
    awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime
}

lock() (
    lock_path=$RUN/$1.lock
    if [ -d "$lock_path" ]; then
        [ "$1" = owner ] && ! alive "$RUN/supervisor.pid" || return 1
        rmdir "$lock_path" 2>/dev/null || return 1
    fi
    candidate=$RUN/$1.candidate.$$
    printf '%s\n' "$IDENTITY" > "$candidate"
    if ! ln "$candidate" "$lock_path" 2>/dev/null; then
        if alive "$lock_path"; then rm -f "$candidate"; return 1; fi
        snapshot_path=$RUN/$1.snapshot.$$
        if ! ln "$lock_path" "$snapshot_path" 2>/dev/null; then rm -f "$candidate"; return 1; fi
        if alive "$snapshot_path"; then rm -f "$candidate" "$snapshot_path"; return 1; fi
        stale_identity=$(cat "$snapshot_path")
        rm -f "$snapshot_path"
        stale_key=$(printf '%s' "$stale_identity" | cksum | awk '{print $1 "-" $2}')
        # Serialize reapers of this identity before touching its successor's pathname.
        reaper=$1.reaper.$stale_key
        if ! lock "$reaper"; then
            rm -f "$candidate"
            return 1
        fi
        if [ "$stale_identity" != "$(cat "$lock_path" 2>/dev/null)" ] || alive "$lock_path"; then
            unlock "$reaper"
            rm -f "$candidate"
            return 1
        fi
        stale_path=$RUN/$1.stale.$$
        if ! mv "$lock_path" "$stale_path" 2>/dev/null; then unlock "$reaper"; rm -f "$candidate"; return 1; fi
        if [ "$stale_identity" != "$(cat "$stale_path" 2>/dev/null)" ] || alive "$stale_path"; then
            ln "$stale_path" "$lock_path" 2>/dev/null || true
            rm -f "$candidate" "$stale_path"
            unlock "$reaper"
            return 1
        fi
        rm -f "$stale_path"
        if ! ln "$candidate" "$lock_path" 2>/dev/null; then unlock "$reaper"; rm -f "$candidate"; return 1; fi
        unlock "$reaper"
    fi
    rm -f "$candidate"
)

wait_control() {
    for _lock_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        lock control && return 0
        sleep 0.1
    done
    return 1
}

unlock() {
    [ "$(cat "$RUN/$1.lock" 2>/dev/null)" = "$IDENTITY" ] || return 0
    rm -f "$RUN/$1.lock"
}

owns() {
    [ "$(cat "$RUN/owner.lock" 2>/dev/null)" = "$IDENTITY" ] &&
        [ "${generation:-}" = "$(cat "$RUN/generation" 2>/dev/null)" ]
}

claim_owner() {
    lock owner || return 1
    generation=$(cat "$RUN/generation" 2>/dev/null) || generation=0
    case "$generation" in ''|*[!0-9]*) generation=0 ;; esac
    generation=$((generation + 1))
    printf '%s\n' "$generation" > "$RUN/generation.tmp"
    mv "$RUN/generation.tmp" "$RUN/generation"
}

rotate_log() {
    if [ -f "$R/logs/$1.log" ] && [ "$(stat -c %s "$R/logs/$1.log")" -ge 1048576 ]; then
        mv "$R/logs/$1.log" "$R/logs/$1.log.1"
    fi
}

runtime_log() {
    rotate_log "$1"
    printf '%s %s\n' "$(boot_seconds)" "$2" >> "$R/logs/$1.log"
}

heartbeat() {
    printf '{"schemaVersion":1,"pid":%s,"startTicks":%s,"bootId":"%s","bootMs":%s000,"sessionId":"%s"}\n' \
        "$$" "$(ticks "$$")" "$BOOT" "$(boot_seconds)" "$generation" > "$RUN/$1.heartbeat.tmp"
    mv "$RUN/$1.heartbeat.tmp" "$RUN/$1.heartbeat"
}

fresh() {
    alive "$RUN/$1.pid" || return 1
    beat=$(cat "$RUN/$1.heartbeat" 2>/dev/null) || return 1
    case "$beat" in *\"pid\":$recorded_pid,\"startTicks\":$recorded_ticks,\"bootId\":\"$BOOT\"*) ;; *) return 1 ;; esac
    beat_ms=$(printf '%s\n' "$beat" | sed -n 's/.*"bootMs":\([0-9]*\),.*/\1/p')
    [ -n "$beat_ms" ] || return 1
    beat_age=$(($(boot_seconds) - beat_ms / 1000))
    [ "$beat_age" -ge 0 ] && [ "$beat_age" -le 5 ]
}

detach() {
    nohup setsid /system/bin/sh "$R/scripts/runtime.sh" spawn "$@" </dev/null >/dev/null 2>&1 &
}

ensure_watchdog() {
    fresh watchdog && return 0
    if alive "$RUN/watchdog.pid"; then kill -KILL "$recorded_pid"; fi
    detach watchdog
}

publish() {
    owns || return 1
    if [ "$1" = running ]; then : > "$R/logs/restore-diff.txt"; fi
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

network_snapshot() {
    snapshot_prefix=$1
    for family in -4 -6; do
        ip "$family" rule show > "$STATE/$snapshot_prefix.$family.rules" || return 1
        ip "$family" route show table all > "$STATE/$snapshot_prefix.$family.routes" || return 1
    done
    iptables-save > "$STATE/$snapshot_prefix.iptables" || return 1
    ip6tables-save > "$STATE/$snapshot_prefix.ip6tables" || return 1
}

baseline() {
    network_snapshot baseline || return 1
    ip link show > "$STATE/baseline.links" || return 1
    ip addr show > "$STATE/baseline.addr" || return 1
}

normalize() {
    sed -E '/^[[:space:]]*#/d; s/\[[0-9]+:[0-9]+\]/[0:0]/g; s/ -c [0-9]+ [0-9]+//g;
        s/ -m comment//g; s/ --comment "([^"\\]|\\.)*"//g; s/ --comment [^[:space:]]+//g;
        s/ expires [0-9]+(sec|msec|ms|s)?//g; s/ age [0-9]+(sec|msec|ms|s)?//g;
        s/ used [0-9]+//g; s/ proto (ra|kernel)( |$)/\2/g' "$1"
}

compare_restoration() {
    diff_file=$R/logs/restore-diff.txt
    : > "$diff_file.tmp"
    if ! network_snapshot restored; then
        printf '%s\n' 'CLEANUP_FAILED: could not collect restored network' >> "$diff_file.tmp"
        mv "$diff_file.tmp" "$diff_file"
        printf '%s WARN CLEANUP_FAILED: network snapshot unavailable; see restore-diff.txt\n' "$(date +%s)" >> "$R/logs/transitions.log"
        return 1
    fi
    comparison_ok=1
    for item in -4.rules -6.rules -4.routes -6.routes iptables ip6tables; do
        if [ ! -f "$STATE/baseline.$item" ]; then
            printf 'CLEANUP_FAILED: missing baseline.%s\n' "$item" >> "$diff_file.tmp"
            comparison_ok=0
            continue
        fi
        normalize "$STATE/baseline.$item" > "$STATE/compare.before" || comparison_ok=0
        normalize "$STATE/restored.$item" > "$STATE/compare.after" || comparison_ok=0
        case "$item" in
            *.rules|*.routes)
                LC_ALL=C sort "$STATE/compare.before" > "$STATE/compare.before.sorted"
                LC_ALL=C sort "$STATE/compare.after" > "$STATE/compare.after.sorted"
                mv "$STATE/compare.before.sorted" "$STATE/compare.before"
                mv "$STATE/compare.after.sorted" "$STATE/compare.after"
                ;;
        esac
        if diff -u "$STATE/compare.before" "$STATE/compare.after" > "$STATE/compare.diff" 2>&1; then
            continue
        else
            diff_result=$?
            printf '\n[%s]\n' "$item" >> "$diff_file.tmp"
            cat "$STATE/compare.diff" >> "$diff_file.tmp"
            [ "$diff_result" -eq 1 ] || comparison_ok=0
        fi
    done
    mv "$diff_file.tmp" "$diff_file"
    if [ -s "$diff_file" ]; then
        printf '%s WARN CLEANUP_FAILED: network differs from baseline; see restore-diff.txt\n' "$(date +%s)" >> "$R/logs/transitions.log"
    fi
    [ "$comparison_ok" -eq 1 ]
}

install_rules() {
    owns || return 1
    vacant || return 1
    baseline || return 1
    # The reservation is written before any network mutation; rollback only touches this namespace.
    printf '%s\n' "$BOOT" > "$STATE/owned.boot"
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
    iptables -w 1 -A FCR_OUTPUT ! -o flcrtun0 -j REJECT || return 1
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
    owns || return 1
    if [ -f "$STATE/owned" ] && [ "$(cat "$STATE/owned.boot" 2>/dev/null)" != "$BOOT" ]; then
        if [ ! -f "$STATE/owned.boot" ] && alive "$RUN/core.pid"; then
            printf '%s\n' "$BOOT" > "$STATE/owned.boot"
        else
            vacant || return 1
            rm -f "$STATE/owned" "$STATE/owned.boot"
        fi
    fi
    stop_core || return 1
    if [ ! -f "$STATE/owned" ]; then
        vacant || return 1
        if [ -f "$STATE/baseline.iptables" ]; then compare_restoration
        else : > "$R/logs/restore-diff.txt"; fi
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
    compare_restoration || return 1
    rm -f "$STATE/owned" "$STATE/owned.boot"
}

launch_core() {
    owns && [ ! -f "$RUN/stop" ] || return 1
    if [ -f "$R/logs/core.log" ] && [ "$(stat -c %s "$R/logs/core.log")" -gt 1048576 ]; then
        mv "$R/logs/core.log" "$R/logs/core.log.1"
    fi
    "$CORE" -d "$R/config" -f "$R/config/config.yaml" >> "$R/logs/core.log" 2>&1 &
    core_pid=$!
    core_ticks=$(ticks "$core_pid")
    [ -n "$core_ticks" ] || return 1
    printf '%s %s %s\n' "$core_pid" "$core_ticks" "$(cat /proc/sys/kernel/random/boot_id)" > "$RUN/core.pid"
}

core_healthy() {
    alive "$RUN/core.pid" || return 1
    ip link show flcrtun0 2>/dev/null | grep -q UP || return 1
    port=$(cat "$R/config/controller.port")
    timeout -s KILL 1 nc -w 1 127.0.0.1 "$port" < "$R/config/health.http" 2>/dev/null | head -n 1 | grep -q ' 200 ' || return 1
}

network_intact() {
    ip -4 route show table 2022 | grep -q flcrtun0 &&
        iptables -w 1 -C OUTPUT -j FCR_OUTPUT && ip6tables -w 1 -C OUTPUT -j FCR_OUTPUT
}

supervise() {
    claim_owner || return 1
    if [ -f "$RUN/stop" ]; then unlock owner; return 0; fi
    if [ "${1:-}" = adopt ]; then publish recovering CORE_CRASHED_RECOVERING; else publish starting; fi
    printf '%s\n' "$IDENTITY" > "$RUN/supervisor.pid"
    heartbeat supervisor
    ensure_watchdog
    for _ready_attempt in 1 2 3 4 5 6 7 8 9 10; do
        fresh watchdog && break
        sleep 0.1
    done
    if ! fresh watchdog; then
        publish stopping CORE_RECOVERY_FAILED
        if cleanup; then publish failed CORE_RECOVERY_FAILED; else publish stopping CLEANUP_FAILED; fi
        rm -f "$RUN/supervisor.pid" "$RUN/supervisor.heartbeat"
        unlock owner
        return 1
    fi
    trap 'touch "$RUN/stop"' TERM INT HUP
    rm -f "$RUN/healthy"
    adopt_ready=0
    if [ "${1:-}" = adopt ]; then
        adopt_deadline=$(cat "$RUN/adopt-deadline" 2>/dev/null) || adopt_deadline=$(($(boot_seconds) + 24))
        while [ ! -f "$RUN/stop" ] && [ "$(boot_seconds)" -lt "$adopt_deadline" ]; do
            heartbeat supervisor
            if core_healthy && network_intact; then adopt_ready=1; break; fi
            sleep 1
        done
    fi
    if [ "${1:-}" = adopt ] && [ "$adopt_ready" -eq 1 ]; then
        [ -f "$STATE/owned.boot" ] || printf '%s\n' "$BOOT" > "$STATE/owned.boot"
        if ! iptables -w 1 -C FCR_OUTPUT ! -o flcrtun0 -j REJECT; then
            if ! iptables -w 1 -A FCR_OUTPUT ! -o flcrtun0 -j REJECT; then
                publish stopping CORE_RECOVERY_FAILED
                if cleanup; then publish failed CORE_RECOVERY_FAILED; else publish stopping CLEANUP_FAILED; fi
                unlock owner
                return 1
            fi
        fi
        publish running CORE_RECOVERED
    elif [ "${1:-}" = adopt ]; then
        publish stopping CORE_RECOVERY_FAILED
        if cleanup; then publish failed CORE_RECOVERY_FAILED; else publish stopping CLEANUP_FAILED; fi
        rm -f "$RUN/supervisor.pid" "$RUN/supervisor.heartbeat"
        unlock owner
        return 1
    fi
    if [ "${1:-}" != adopt ] && [ ! -c /dev/net/tun ]; then
        publish failed TUN_DEVICE_UNSUPPORTED
    elif [ "${1:-}" != adopt ] && ! install_rules; then
        publish stopping NETWORK_RULES_APPLY_FAILED
        if cleanup; then publish failed NETWORK_RULES_APPLY_FAILED; else publish stopping CLEANUP_FAILED; fi
    elif [ "${1:-}" != adopt ] && ! launch_core; then
        if cleanup; then publish failed CORE_START_FAILED; else publish stopping CLEANUP_FAILED; fi
    else
        deadline=$(($(boot_seconds) + 9))
        crash_times=''
        if [ -f "$RUN/crash-times" ]; then
            read -r crash_boot crash_times < "$RUN/crash-times"
            [ "$crash_boot" = "$BOOT" ] || crash_times=''
        fi
        final_code=''
        while owns && [ ! -f "$RUN/stop" ]; do
            heartbeat supervisor
            ensure_watchdog
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
                printf '%s %s\n' "$BOOT" "$crash_times" > "$RUN/crash-times.tmp"
                mv "$RUN/crash-times.tmp" "$RUN/crash-times"
                [ "$crash_count" -lt 3 ] || { final_code=CORE_CRASH_LOOP; break; }
                publish recovering CORE_CRASHED_RECOVERING
                rm -f "$RUN/healthy"
                recovery_deadline=${recovery_deadline:-$((now + 26))}
                stop_core
                runtime_log supervisor "recovery begin bootSeconds=$now deadline=$recovery_deadline"
                if ! launch_core; then final_code=CORE_RECOVERY_FAILED; break; fi
                deadline=$recovery_deadline
            fi
            rm -f "$RUN/healthy"
            if core_healthy; then touch "$RUN/healthy"; fi
            if [ -f "$RUN/healthy" ]; then
                current=$(cat "$STATE/status")
                case "$current" in
                    recovering*)
                        runtime_log supervisor "recovery end bootSeconds=$now"
                        publish running CORE_RECOVERED
                        unset recovery_deadline
                        ;;
                    starting*) publish running ;;
                esac
                deadline=$((now + 26))
                if ! network_intact; then
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
    owns || return 0
    rm -f "$RUN/supervisor.pid" "$RUN/supervisor.heartbeat" "$RUN/healthy"
    unlock owner
}

package_status() {
    path_result=0
    package_path=$(timeout -s KILL 1 pm path com.follow.clash.root 2>&1) || path_result=$?
    case "$path_result" in 0|1) ;; *) echo unknown; return ;; esac
    if [ "$path_result" -eq 1 ] && [ -n "$package_path" ]; then echo unknown; return; fi
    # Android returns 1 for an absent package; a successful exact list query must corroborate it.
    package_list=$(timeout -s KILL 1 pm list packages com.follow.clash.root 2>&1) || { echo unknown; return; }
    if [ -d /data/data/com.follow.clash.root ]; then echo present; return; fi
    if printf '%s\n' "$package_list" | grep -v -E '^(package:[A-Za-z0-9_.]+)?$' | grep -q .; then echo unknown; return; fi
    if printf '%s\n' "$package_list" | grep -qx 'package:com.follow.clash.root'; then
        if [ -n "$package_path" ] && ! printf '%s\n' "$package_path" | grep -v '^package:/[^[:space:]]*$' | grep -q .; then
            echo present
        else echo unknown; fi
    elif [ -z "$package_path" ]; then echo absent
    else echo unknown; fi
}

own_entry() {
    [ ! -L /data/adb/service.d ] && [ ! -L /data/adb/service.d/flclash-root.sh ] &&
        [ -f /data/adb/service.d/flclash-root.sh ] &&
        grep -qx '# flclash-root service.d v[12]' /data/adb/service.d/flclash-root.sh
}

remove_entry() {
    if own_entry; then rm -f /data/adb/service.d/flclash-root.sh; fi
}

stop_boot() {
    if alive "$RUN/boot.lock" && [ "$recorded_pid" != "$$" ]; then kill -TERM "$recorded_pid"; fi
}

uninstall_runtime() {
    lock control || return 1
    touch "$RUN/stop"
    stop_boot
    if alive "$RUN/supervisor.pid"; then kill -KILL "$recorded_pid"; fi
    if ! claim_owner; then unlock control; return 1; fi
    publish stopping
    if ! cleanup; then
        publish stopping CLEANUP_FAILED
        log -t FlClashRoot 'uninstall confirmed; CLEANUP_FAILED, retrying' 2>/dev/null || true
        unlock owner
        unlock control
        return 1
    fi
    remove_entry || { unlock owner; unlock control; return 1; }
    log -t FlClashRoot 'com.follow.clash.root uninstall confirmed; cleanup complete; removing runtime' 2>/dev/null || true
    if alive "$RUN/watchdog.pid" && [ "$recorded_pid" != "$$" ]; then kill -TERM "$recorded_pid"; fi
    rm -rf "$R"
}

record_package_status() {
    case "$1" in
        absent) missing_count=$((missing_count + 1)) ;;
        *) missing_count=0 ;;
    esac
    [ "$missing_count" -ge 2 ] || return 1
    runtime_log watchdog 'uninstall confirmed for com.follow.clash.root'
    uninstall_runtime
}

check_uninstall() {
    record_package_status "$(package_status)"
}

write_settings() {
    root_enabled=false
    auto_enabled=false
    [ "$(cat "$R/config/root-tun-enabled" 2>/dev/null)" != 1 ] || root_enabled=true
    [ "$(cat "$R/config/autostart-enabled" 2>/dev/null)" != 1 ] || auto_enabled=true
    printf '{"schemaVersion":1,"rootTunEnabled":%s,"autostartEnabled":%s}\n' \
        "$root_enabled" "$auto_enabled" > "$R/config/settings.json.tmp" &&
        mv "$R/config/settings.json.tmp" "$R/config/settings.json"
}

boot_failure() {
    runtime_log boot "$1"
    lock control || return 1
    if ! fresh supervisor && claim_owner; then
        publish stopping "$1"
        if cleanup; then publish failed "$1"; else publish stopping CLEANUP_FAILED; fi
        unlock owner
    fi
    unlock control
}

autostart_requested() {
    if [ ! -f "$R/config/settings.json" ]; then
        for setting in root-tun-enabled autostart-enabled; do
            case "$(cat "$R/config/$setting" 2>/dev/null)" in 0|1) ;; *) return 2 ;; esac
        done
        write_settings || return 2
    fi
    grep -Eqx '\{"schemaVersion":1,"rootTunEnabled":(true|false),"autostartEnabled":(true|false)\}' "$R/config/settings.json" || return 2
    grep -qx '{"schemaVersion":1,"rootTunEnabled":true,"autostartEnabled":true}' "$R/config/settings.json"
}

user_unlocked() {
    user_state=$(timeout -s KILL 3 am get-started-user-state 0 2>/dev/null) || user_state=''
    [ "$user_state" = RUNNING_UNLOCKED ] ||
        [ "$(getprop sys.user.0.ce_available 2>/dev/null)" = true ]
}

prune_boot_markers() {
    for old_marker in "$RUN"/boot-*; do
        [ -d "$old_marker" ] && [ ! -L "$old_marker" ] || continue
        marker_id=${old_marker##*/boot-}
        if printf '%s\n' "$marker_id" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
            rmdir "$old_marker" 2>/dev/null || true
        fi
    done
}

bootstrap() {
    lock boot || return 0
    prune_boot_markers
    trap 'unlock boot' EXIT
    trap 'exit 0' TERM INT HUP
    boot_deadline=$(($(boot_seconds) + 120))
    while [ "$(getprop sys.boot_completed)" != 1 ]; do
        if [ "$(boot_seconds)" -ge "$boot_deadline" ]; then boot_failure AUTOSTART_FAILED; return 1; fi
        sleep 2
    done
    unlock_deadline=$(($(boot_seconds) + 300))
    while ! user_unlocked; do
        if [ "$(boot_seconds)" -ge "$unlock_deadline" ]; then boot_failure AUTOSTART_FAILED; return 1; fi
        sleep 2
    done
    dependency_deadline=$(($(boot_seconds) + 50))
    missing_count=0
    next_package_check=0
    while :; do
        now=$(boot_seconds)
        if [ "$now" -ge "$next_package_check" ]; then
            next_package_check=$((now + 10))
            check_uninstall && return 0
        fi
        package=$(package_status)
        if [ "$package" = present ]; then
            settings_result=0
            autostart_requested || settings_result=$?
            case "$settings_result" in
                1) return 0 ;;
                2) boot_failure AUTOSTART_FAILED; return 1 ;;
            esac
        fi
        if [ "$package" = present ] && ip -4 route show table all | grep -E '^default .* (via|dev) |^default (via|dev) ' | grep -v flcrtun0 >/dev/null; then break; fi
        if [ "$now" -ge "$dependency_deadline" ]; then boot_failure AUTOSTART_FAILED; return 1; fi
        sleep 2
    done
    [ "$(cat "$RUN/boot-id" 2>/dev/null)" != "$BOOT" ] || return 0
    case "$(manager_authorization)" in
        granted) ;;
        denied) revoke_runtime AUTOSTART_ROOT_REVOKED; return 1 ;;
        *) boot_failure AUTOSTART_FAILED; return 1 ;;
    esac
    if [ ! -s "$R/config/config.yaml" ] || [ ! -x "$CORE" ]; then boot_failure AUTOSTART_FAILED; return 1; fi
    if [ "$(boot_seconds)" -gt "$dependency_deadline" ]; then boot_failure AUTOSTART_FAILED; return 1; fi
    start_deadline=$(($(boot_seconds) + 10))
    printf '%s\n' "$BOOT" > "$RUN/boot-id.tmp" && mv "$RUN/boot-id.tmp" "$RUN/boot-id"
    runtime_log boot 'autostart submitted'
    /system/bin/sh "$R/scripts/runtime.sh" start || { boot_failure AUTOSTART_FAILED; return 1; }
    saw_start=0
    while [ "$(boot_seconds)" -lt "$start_deadline" ]; do
        [ "$(cat "$STATE/auth-status" 2>/dev/null)" != revoked ] || return 1
        case "$(cat "$STATE/status" 2>/dev/null)" in
            running*) runtime_log boot 'autostart running'; return 0 ;;
            starting*|recovering*) saw_start=1 ;;
            failed*) if [ "$saw_start" -eq 1 ]; then boot_failure AUTOSTART_FAILED; return 1; fi ;;
        esac
        sleep 1
    done
    boot_failure AUTOSTART_FAILED
}

revoke_runtime() {
    lock control || return 1
    printf '%s\n' "$1" > "$STATE/revocation-code"
    touch "$RUN/stop"
    stop_boot
    if alive "$RUN/supervisor.pid"; then kill -KILL "$recorded_pid"; fi
    if ! claim_owner; then unlock control; return 1; fi
    publish stopping "$1"
    if cleanup && remove_entry; then
        echo 0 > "$R/config/autostart-enabled"
        write_settings
        printf '%s\n' revoked > "$STATE/auth-status"
        [ -f "$STATE/revoked-since" ] || boot_seconds > "$STATE/revoked-since"
        publish failed "$1"
        runtime_log watchdog "$1 cleanup complete"
        cmd notification post -t 'FlClash Root TUN' flclash-root "$1" >/dev/null 2>&1 || true
        notify_app_cleanup "$1"
        if ! alive "$RUN/watchdog.pid"; then detach watchdog; fi
        result=0
    else
        publish stopping CLEANUP_FAILED
        result=1
    fi
    unlock owner
    unlock control
    return "$result"
}

record_authorization() {
    manager_auth=$1
    case "$manager_auth" in
        denied) denied_count=$((denied_count + 1)) ;;
        *) denied_count=0 ;;
    esac
    app_auth=$2
    runtime_log watchdog "authorization manager=$manager_auth app=$app_auth"
    if [ "$denied_count" -ge 2 ] || [ "$app_auth" = revoked ]; then revoke_runtime ROOT_PERMISSION_REVOKED; fi
}

start_probe() {
    if alive "$RUN/$1-probe.pid"; then return 0; fi
    probe_id="$$-$(boot_seconds)"
    rm -f "$RUN/$1.result"
    /system/bin/sh "$R/scripts/runtime.sh" "probe-$1" "$probe_id" </dev/null >/dev/null 2>&1 &
    probe_pid=$!
    printf '%s %s %s\n' "$probe_pid" "$(ticks "$probe_pid")" "$BOOT" > "$RUN/$1-probe.pid"
    printf '%s\n' "$probe_id" > "$RUN/$1-probe.id"
}

stop_probes() {
    for probe in package auth; do
        if alive "$RUN/$probe-probe.pid"; then kill -TERM "$recorded_pid" 2>/dev/null || true; fi
        rm -f "$RUN/$probe-probe.pid" "$RUN/$probe-probe.id" "$RUN/$probe.result"
    done
}

authorization_interval() {
    if [ -f "$RUN/stop" ] && [ ! -f "$STATE/owned" ] && [ "$(cat "$STATE/status" 2>/dev/null)" = 'disabled -' ]; then
        echo 15
    else
        echo 2
    fi
}

watchdog() {
    lock watchdog || return 0
    trap 'stop_probes; rm -f "$RUN/watchdog.pid" "$RUN/watchdog.heartbeat"; unlock watchdog' EXIT
    trap 'exit 0' TERM INT HUP
    printf '%s\n' "$IDENTITY" > "$RUN/watchdog.pid"
    generation=$(cat "$RUN/generation" 2>/dev/null) || generation=0
    runtime_log watchdog 'watchdog started'
    orphan_since=0
    missing_count=0
    denied_count=0
    next_auth_check=0
    auth_check_interval=2
    next_package_check=0
    while :; do
        heartbeat watchdog
        if [ -f "$STATE/revocation-code" ] && [ "$(cat "$STATE/auth-status" 2>/dev/null)" != revoked ]; then
            revoke_runtime "$(cat "$STATE/revocation-code")" || true
            if [ "$(cat "$STATE/auth-status" 2>/dev/null)" != revoked ]; then sleep 1; continue; fi
        fi
        if [ -f "$RUN/package.result" ]; then
            read -r result_id package_result < "$RUN/package.result"
            rm -f "$RUN/package.result"
            if [ "$result_id" = "$(cat "$RUN/package-probe.id" 2>/dev/null)" ]; then
                record_package_status "$package_result" && return 0
            fi
        fi
        if [ -f "$RUN/auth.result" ]; then
            read -r result_id manager_result app_result < "$RUN/auth.result"
            rm -f "$RUN/auth.result"
            if [ "$result_id" = "$(cat "$RUN/auth-probe.id" 2>/dev/null)" ] &&
                [ "$(cat "$STATE/auth-status" 2>/dev/null)" != revoked ]; then record_authorization "$manager_result" "$app_result"; fi
        fi
        if [ "$(boot_seconds)" -ge "$next_package_check" ]; then
            next_package_check=$(($(boot_seconds) + 10))
            start_probe package
        fi
        current_auth_interval=$(authorization_interval)
        if [ "$current_auth_interval" -ne "$auth_check_interval" ]; then
            auth_check_interval=$current_auth_interval
            next_auth_check=0
        fi
        if [ "$(boot_seconds)" -ge "$next_auth_check" ]; then
            next_auth_check=$(($(boot_seconds) + auth_check_interval))
            start_probe auth
        fi
        if [ "$(cat "$STATE/auth-status" 2>/dev/null)" = revoked ]; then
            revoked_since=$(cat "$STATE/revoked-since" 2>/dev/null) || revoked_since=$(boot_seconds)
            if [ $(($(boot_seconds) - revoked_since)) -ge 600 ]; then
                runtime_log watchdog 'revocation monitoring expired after cleanup'
                return 0
            fi
            sleep 1
            continue
        fi
        if [ ! -f "$STATE/owned" ]; then
            case "$(cat "$STATE/status" 2>/dev/null)" in
                disabled*|failed*) sleep 1; continue ;;
            esac
        fi
        if ! fresh supervisor && lock control; then
            if fresh supervisor; then unlock control; continue; fi
            if alive "$RUN/supervisor.pid"; then kill -KILL "$recorded_pid"; fi
            [ "$orphan_since" -ne 0 ] || orphan_since=$(boot_seconds)
            if claim_owner; then
                if [ -f "$RUN/stop" ]; then
                    publish stopping
                    if cleanup; then publish disabled; unlock owner; unlock control; sleep 1; continue; fi
                    publish stopping CLEANUP_FAILED
                elif [ $(($(boot_seconds) - orphan_since)) -lt 24 ]; then
                    if core_healthy && network_intact; then
                        runtime_log watchdog "supervisor takeover generation=$generation"
                        printf '%s\n' "$((orphan_since + 24))" > "$RUN/adopt-deadline"
                        heartbeat watchdog
                        unlock owner
                        detach supervise adopt
                        unlock control
                        sleep 1
                    fi
                else
                    runtime_log watchdog 'supervisor/core lost; fail-open cleanup'
                    publish stopping CORE_RECOVERY_FAILED
                    if cleanup; then
                        publish failed CORE_RECOVERY_FAILED
                        unlock owner
                        unlock control
                        sleep 1
                        continue
                    fi
                    publish stopping CLEANUP_FAILED
                fi
                unlock owner
            fi
            unlock control
        else
            orphan_since=0
        fi
        rotate_log watchdog
        sleep 1
    done
}

stop_runtime() {
    printf '%s\n' "$BOOT" > "$RUN/boot-id.tmp" && mv "$RUN/boot-id.tmp" "$RUN/boot-id"
    touch "$RUN/stop"
    stop_boot
    for _wait_count in 1 2 3 4 5 6 7 8 9 10; do
        alive "$RUN/supervisor.pid" || break
        sleep 0.1
    done
    if alive "$RUN/supervisor.pid"; then kill -KILL "$recorded_pid" || return 1; fi
    claim_owner || return 1
    publish stopping
    if ! cleanup; then publish stopping CLEANUP_FAILED; unlock owner; return 1; fi
    publish disabled
    if [ "${1:-stop}" = cleanup ]; then
        if alive "$RUN/watchdog.pid"; then kill -TERM "$recorded_pid"; fi
    else
        ensure_watchdog
    fi
    unlock owner
    rm -f "$RUN/supervisor.pid" "$RUN/supervisor.heartbeat" "$RUN/healthy"
}

safe_tree || exit 1
# shellcheck source=android/app/src/main/assets/root-tun/authorization.sh
. "$R/scripts/authorization.sh"
IDENTITY="$$ $(ticks "$$") $BOOT"
case "${1:-}" in
    probe-package)
        printf '%s %s\n' "$2" "$(package_status)" > "$RUN/package.result.$$"
        mv "$RUN/package.result.$$" "$RUN/package.result"
        ;;
    probe-auth)
        if [ "$(cat "$STATE/auth-status" 2>/dev/null)" = revoked ]; then
            notify_app_cleanup "$(cut -d' ' -f2 "$STATE/status")"
            exit 0
        fi
        printf '%s %s %s\n' "$2" "$(manager_authorization)" "$(app_authorization)" > "$RUN/auth.result.$$"
        mv "$RUN/auth.result.$$" "$RUN/auth.result"
        ;;
    boot) detach bootstrap ;;
    bootstrap) bootstrap ;;
    settings) write_settings ;;
    start)
        if ! wait_control; then exit 1; fi
        if fresh supervisor; then ensure_watchdog; unlock control; exit 0; fi
        printf '%s\n' "$BOOT" > "$RUN/boot-id.tmp" && mv "$RUN/boot-id.tmp" "$RUN/boot-id"
        rm -f "$RUN/stop" "$STATE/auth-status" "$STATE/revocation-code" "$STATE/revoked-since" "$RUN/adopt-deadline"
        if [ ! -f "$STATE/owned" ]; then rm -f "$RUN/crash-times"; fi
        if [ -d "$RUN/owner.lock" ] && [ ! -f "$RUN/generation" ] && core_healthy; then
            if alive "$RUN/supervisor.pid"; then kill -KILL "$recorded_pid"; fi
            rmdir "$RUN/owner.lock" || { unlock control; exit 1; }
            detach supervise adopt
        else detach supervise; fi
        unlock control
        for _start_attempt in 1 2 3 4 5 6 7 8 9 10; do
            if fresh supervisor; then
                case "$(cat "$STATE/status" 2>/dev/null)" in starting*|running*|recovering*) break ;; esac
            fi
            sleep 0.1
        done
        ;;
    spawn)
        shift
        nohup /system/bin/sh "$R/scripts/runtime.sh" "$@" </dev/null >/dev/null 2>&1 &
        ;;
    supervise) supervise "${2:-}" ;;
    watchdog) watchdog ;;
    stop|cleanup)
        wait_control || exit 1
        stop_runtime "$1"
        result=$?
        unlock control
        exit "$result"
        ;;
    status)
        cat "$STATE/status" 2>/dev/null || echo disabled
        printf 'bootMs:%s\n' "$(boot_ms)"
        printf 'auth:%s\n' "$(cat "$STATE/auth-status" 2>/dev/null)"
        printf 'dns:%s\n' "$(cat "$STATE/private-dns" 2>/dev/null)"
        if [ -s "$R/logs/restore-diff.txt" ]; then echo restore-diff:yes; fi
        always_on=$(settings get secure always_on_vpn_app 2>/dev/null)
        if [ "$always_on" = "$(cat "$R/config/app.package" 2>/dev/null)" ]; then echo always-on:yes; fi
        fresh supervisor || exit 1
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
