#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
RUN=$WORK/run
mkdir -p "$RUN"
sed -n '/^refresh_health() {/,/^supervise() {/p' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" | sed '$d' > "$WORK/health.sh"
. "$WORK/health.sh"
core_healthy() { [ "$core" = yes ]; }
configure_routes() {
    route_checks=$((route_checks + 1))
    [ "$routes" = yes ] || return 1
    rp_filter=2
}
network_intact() { [ "$rules" = yes ]; }
core=yes routes=yes rules=yes rp_filter=1 route_checks=0
refresh_health
[ -f "$RUN/healthy" ] && [ "$rp_filter" = 2 ]
rp_filter=1
refresh_health
[ -f "$RUN/healthy" ] && [ "$rp_filter" = 2 ] && [ "$route_checks" -eq 2 ]
echo 'PASS TUN interface recreation reapplies its route policy even when the route still exists'
routes=no
refresh_health
[ ! -f "$RUN/healthy" ] && [ "$health_failure_code" = NETWORK_RULES_APPLY_FAILED ]
routes=yes
refresh_health
[ -f "$RUN/healthy" ]
rules=no
refresh_health
[ ! -f "$RUN/healthy" ] && [ "$health_failure_code" = NETWORK_RULES_APPLY_FAILED ]
rules=yes
refresh_health
[ -f "$RUN/healthy" ]
echo 'PASS transient handover route and firewall gaps can recover before the supervisor deadline'
core=no
refresh_health
[ ! -f "$RUN/healthy" ] && [ "$health_failure_code" = START_TIMEOUT ]
echo 'PASS missing Core readiness is distinct from a pending network policy'

sed -n '/^supervise() {/,/^}/p' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/supervise.sh"
. "$WORK/supervise.sh"
for scenario in transient permanent; do (
    R=$WORK/$scenario
    RUN=$R/run STATE=$R/state
    mkdir -p "$RUN" "$STATE" "$R/config"
    printf '0\n' > "$R/config/tun.enabled"
    BOOT=test-boot IDENTITY='42 1 test-boot' round=0
    claim_owner() { return 0; }
    owns() { return 0; }
    heartbeat() { return 0; }
    ensure_watchdog() { return 0; }
    fresh() { return 0; }
    alive() { return 0; }
    install_rules() { return 0; }
    launch_core() { return 0; }
    cleanup() { return 0; }
    unlock() { return 0; }
    update_private_dns() { return 0; }
    core_healthy() { return 0; }
    configure_routes() {
        [ "$round" -lt 2 ] || { [ "$scenario" = transient ] && [ "$round" -ge 5 ]; }
    }
    network_intact() { configure_routes; }
    boot_seconds() { printf '%s\n' "$round"; }
    boot_ms() { printf '%s\n' "$((round * 1000))"; }
    runtime_log() { printf '%s\n' "$*" >> "$R/events"; }
    publish() {
        printf '%s %s\n' "$1" "${2:--}" > "$STATE/status"
        printf '%s %s %s\n' "$round" "$1" "${2:--}" >> "$R/events"
    }
    sleep() {
        round=$((round + 1))
        if [ "$scenario" = transient ] && [ "$round" -eq 6 ]; then touch "$RUN/stop"; fi
        [ "$round" -lt 35 ] || exit 99
    }
    supervise
    if [ "$scenario" = transient ]; then
        grep -q '^6 stopping -$' "$R/events"
        grep -q '^6 disabled -$' "$R/events"
        ! grep -q 'NETWORK_RULES_APPLY_FAILED' "$R/events"
        echo 'PASS the actual supervisor survives a handover gap without stopping the session'
    else
        grep -q '^27 failed NETWORK_RULES_APPLY_FAILED$' "$R/events"
        echo 'PASS a persistent network fault still stops after the bounded recovery deadline'
    fi
); done
