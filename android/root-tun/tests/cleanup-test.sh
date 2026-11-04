#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=${FLCLASH_TEST_RUNTIME:-$TESTS/../../app/src/main/assets/root-tun/runtime.sh}
TEST_TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TEST_TMP/flclash-cleanup.XXXXXX")
case "$WORK" in "$TEST_TMP"/flclash-cleanup.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
cat > "$WORK/bin/iptables-save" <<'SAVE'
#!/bin/sh
printf '*filter\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n'
SAVE
cp "$WORK/bin/iptables-save" "$WORK/bin/ip6tables-save"
chmod +x "$WORK/bin/iptables-save" "$WORK/bin/ip6tables-save"
export PATH="$WORK/bin:$PATH"
cat > "$WORK/stubs.sh" <<'STUBS'
ticks() { printf '1\n'; }
alive() {
    case "$CASE:$1" in
        "reconcile-active:$RUN/core.pid"|"proxy-repair-live:$RUN/core.pid"|"proxy-repair-live-failure:$RUN/core.pid"|"reconcile-booting:$RUN/boot.lock"|"proxy-repair-booting:$RUN/boot.lock") return 0 ;;
    esac
    return 1
}
root_proxy() {
    printf '%s\n' "$1" >> "$R/proxy-calls"
    case "$CASE" in *proxy-failure|proxy-repair-failure|proxy-repair-live-failure) return 1 ;; esac
    rm -f "$STATE/proxy.json"
}
stat() {
    if [ "$*" = "-c %u $R" ]; then printf '0\n'; else command stat "$@"; fi
}
ip() {
    case "$*" in
        '-4 rule show'|'-6 rule show')
            [ "$CASE" != inspect-rules ] || { echo 'Operation not permitted' >&2; return 2; }
            printf '0: from all lookup local\n10000: from all lookup 99\n32000: from all unreachable\n'
            case "$CASE" in reserved-rules|reconcile-reserved) echo '9000: from all lookup 1234' ;; esac
            ;;
        '-4 route show table 2022'|'-6 route show table 2022')
            case "$CASE" in
                missing-table) echo 'Error: ipv4: FIB table does not exist.' >&2; return 2 ;;
                inspect-routes) echo 'Operation not permitted' >&2; return 2 ;;
                reserved-table) echo 'default dev foreign0' ;;
            esac
            ;;
        '-4 route show table all'|'-6 route show table all'|'-4 route flush table 2022'|'-6 route flush table 2022') : ;;
        'link show flcrtun0') return 1 ;;
        'link show')
            echo '1: lo: <LOOPBACK,UP>'
            [ "$CASE" != reserved-link ] || echo '2: flcrtun0: <UP>'
            ;;
        *) echo "Unexpected network command: $*" >&2; exit 99 ;;
    esac
    return 0
}
iptables() {
    case "$*" in
        '-w 1 -C OUTPUT -j FCR_OUTPUT'|'-w 1 -S FCR_OUTPUT') return 1 ;;
        '-w 1 -S') ;;
        '-w 1 -t nat -S')
            case "$CASE" in
                missing-ipv4-nat) echo "iptables v1.8.11 (legacy): can't initialize iptables table \`nat': Table does not exist (do you need to insmod?)" >&2; return 3 ;;
                denied-nat) echo 'Permission denied (you must be root)' >&2; return 4 ;;
                occupied-nat) echo '-N mihomo-output' ;;
                owned-empty-redirect|owned-referenced-empty-redirect|owned-foreign-empty-redirect|owned-foreign-redirect)
                    [ -f "$R/redirect-removed" ] || echo '-N mihomo-output'
                    ;;
            esac
            ;;
        '-w 1 -t nat -S mihomo-output')
            case "$CASE" in
                owned-empty-redirect|owned-referenced-empty-redirect|owned-foreign-empty-redirect) echo '-N mihomo-output' ;;
                owned-foreign-redirect) printf '%s\n' '-N mihomo-output' '-A mihomo-output -o foreign0 -j RETURN' ;;
                *) return 1 ;;
            esac
            ;;
        '-w 1 -t nat -X mihomo-output')
            [ "$CASE" = owned-empty-redirect ] || return 1
            touch "$R/redirect-removed"
            ;;
        *) exit 99 ;;
    esac
    [ "$CASE" != inspect-firewall ] || { echo 'Permission denied' >&2; return 3; }
    [ "$CASE" != reserved-chain ] || echo '-N FCR_OUTPUT'
    return 0
}
ip6tables() {
    if [ "$*" = '-w 1 -t nat -S' ]; then
        case "$CASE" in
            missing-ipv6-nat) echo "ip6tables v1.8.11 (legacy): can't initialize ip6tables table \`nat': Table does not exist (do you need to insmod?)" >&2; return 3 ;;
            denied-ipv6-nat) echo 'Permission denied (you must be root)' >&2; return 4 ;;
            broken-ipv6-nat) echo 'ip6tables: incompatible kernel/userspace version' >&2; return 3 ;;
        esac
    fi
    iptables "$@"
}
STUBS
for scenario in incomplete stale-script missing-table missing-ipv6-nat previous-boot previous-boot-proxy previous-boot-proxy-failure orphan-proxy reconcile-previous reconcile-unowned reconcile-previous-proxy-failure reconcile-current reconcile-active reconcile-booting reconcile-reserved proxy-repair-orphan proxy-repair-failure proxy-repair-live proxy-repair-live-failure proxy-repair-booting owned owned-empty-redirect owned-referenced-empty-redirect owned-foreign-empty-redirect owned-foreign-redirect reserved-rules inspect-rules inspect-routes reserved-table reserved-link reserved-chain inspect-firewall missing-ipv4-nat denied-nat denied-ipv6-nat broken-ipv6-nat occupied-nat unsafe-tree; do
    R=$WORK/$scenario
    mkdir -p "$R"
    if [ "$scenario" = stale-script ]; then
        mkdir -p "$R/scripts"
        printf 'echo stale-script-was-executed >&2\nexit 91\n' > "$R/scripts/runtime.sh"
    fi
    case "$scenario" in
        previous-boot*|reconcile-*|owned*)
            mkdir -p "$R/state"
            printf 'reserved\n' > "$R/state/owned"
            case "$scenario" in
            owned*)
                printf 'test-boot\n' > "$R/state/owned.boot"
                for item in -4.rules -6.rules; do
                    printf '0: from all lookup local\n10000: from all lookup 99\n32000: from all unreachable\n' > "$R/state/baseline.$item"
                done
                for item in -4.routes -6.routes; do : > "$R/state/baseline.$item"; done
                for item in iptables ip6tables; do
                    printf '*filter\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$R/state/baseline.$item"
                done
                [ "$scenario" != owned-foreign-empty-redirect ] || printf ':mihomo-output - [0:0]\n' >> "$R/state/baseline.iptables"
                ;;
            *)
                printf 'previous-boot\n' > "$R/state/owned.boot"
                mkdir -p "$R/run"
                printf 'previous-boot\n' > "$R/run/boot-id"
                printf 'old OS firewall baseline\n' > "$R/state/baseline.iptables"
                ;;
            esac
            ;;
    esac
    case "$scenario" in
        proxy-repair-*)
            mkdir -p "$R/config"
            printf '127.0.0.1:7890' > "$R/config/system-proxy"
            ;;
    esac
    case "$scenario" in
        *proxy*|reconcile-previous)
            mkdir -p "$R/state"
            printf 'recorded previous and applied proxy\n' > "$R/state/proxy.json"
            ;;
    esac
    [ "$scenario" != reconcile-current ] || printf 'test-boot\n' > "$R/run/boot-id"
    [ "$scenario" != reconcile-unowned ] || rm -f "$R/state/owned" "$R/state/owned.boot"
    [ "$scenario" != proxy-repair-orphan ] || rm -f "$R/state/proxy.json"
    if [ "$scenario" = reconcile-booting ]; then
        mkdir -p "$R/config"
        printf '1\n' > "$R/config/autostart-enabled"
    fi
    sed -e "s|^R=/data/adb/flclash-root$|R='$R'|" \
        -e 's|^BOOT=.*|BOOT=test-boot|' -e '/^export PATH=/d' \
        -e "/^safe_tree || exit 1/i\\
. '$WORK/stubs.sh'" "$SOURCE" > "$WORK/current-runtime.sh"
    export CASE=$scenario
    operation=cleanup
    case "$scenario" in reconcile-*) operation=reconcile-boot ;; proxy-repair-*) operation=repair-proxy ;; esac
    if [ "$scenario" = unsafe-tree ]; then
        sed "s|\[ ! -L \"\$R\" \]|[ false = true ]|" "$WORK/current-runtime.sh" > "$WORK/unsafe-runtime.sh"
        cp "$WORK/unsafe-runtime.sh" "$WORK/current-runtime.sh"
    fi
    result=0
    sh "$WORK/current-runtime.sh" "$operation" > "$WORK/stdout" 2> "$WORK/stderr" || result=$?
    case "$scenario" in
        incomplete|stale-script|missing-table|missing-ipv6-nat|previous-boot|previous-boot-proxy|orphan-proxy|reconcile-previous|reconcile-unowned|proxy-repair-orphan|owned|owned-empty-redirect)
            if [ "$result" -ne 0 ]; then cat "$WORK/stderr" >&2; exit 1; fi
            grep -q '^disabled ' "$R/state/status"
            [ ! -e "$R/run/owner.lock" ] && [ ! -e "$R/run/control.lock" ]
            [ ! -f "$R/state/owned" ] && [ ! -f "$R/state/owned.boot" ]
            [ ! -f "$R/state/proxy.json" ]
            case "$scenario" in *proxy|reconcile-previous) [ "$(cat "$R/proxy-calls")" = restore ] ;; esac
            [ "$scenario" != reconcile-previous ] || [ ! -f "$R/run/boot-id" ]
            if [ "$scenario" = reconcile-previous ]; then
                sh "$WORK/current-runtime.sh" reconcile-boot
                [ "$(wc -l < "$R/logs/transitions.log" | tr -d ' ')" = 2 ]
                [ "$(wc -l < "$R/proxy-calls" | tr -d ' ')" = 1 ]
            fi
            [ ! -s "$WORK/stderr" ]
            [ "$scenario" != proxy-repair-orphan ] || [ ! -s "$R/config/system-proxy" ]
            [ "$scenario" != owned-empty-redirect ] || [ -f "$R/redirect-removed" ]
            ;;
        owned-referenced-empty-redirect|owned-foreign-empty-redirect|owned-foreign-redirect)
            [ "$result" -ne 0 ] && [ -f "$R/state/owned" ]
            [ ! -f "$R/redirect-removed" ]
            grep -q '^stopping CLEANUP_FAILED$' "$R/state/status"
            ;;
        proxy-repair-failure)
            [ "$result" -ne 0 ]
            [ -s "$R/config/system-proxy" ]
            grep -q '^stopping CLEANUP_FAILED$' "$R/state/status"
            ;;
        *proxy-failure)
            [ "$result" -ne 0 ]
            [ -f "$R/state/owned" ] && [ -f "$R/state/proxy.json" ]
            [ "$(cat "$R/state/owned.boot")" = previous-boot ]
            grep -q '^stopping CLEANUP_FAILED$' "$R/state/status"
            grep -q 'root-runtime: step=restore-proxy ' "$WORK/stderr"
            [ "$scenario" != reconcile-previous-proxy-failure ] || [ "$(cat "$R/run/boot-id")" = previous-boot ]
            ;;
        proxy-repair-live|proxy-repair-live-failure|proxy-repair-booting)
            [ ! -f "$R/state/status" ] && [ ! -f "$R/run/stop" ] && [ ! -f "$R/run/owner.lock" ]
            if [ "$scenario" = proxy-repair-live ]; then
                [ "$result" -eq 0 ] && [ "$(cat "$R/proxy-calls")" = restore ]
                [ ! -s "$R/config/system-proxy" ] && [ ! -f "$R/state/proxy.json" ]
                grep -q '^proxy-repair:verified$' "$WORK/stdout"
            elif [ "$scenario" = proxy-repair-booting ]; then
                [ "$result" -eq 0 ] && [ ! -f "$R/proxy-calls" ]
                [ -s "$R/config/system-proxy" ] && [ -f "$R/state/proxy.json" ]
                grep -q '^proxy-repair:deferred$' "$WORK/stdout"
            else
                [ "$result" -ne 0 ] && [ -s "$R/config/system-proxy" ] && [ -f "$R/state/proxy.json" ]
                ! grep -q '^proxy-repair:verified$' "$WORK/stdout"
            fi
            ;;
        reconcile-current|reconcile-active|reconcile-booting)
            [ "$result" -eq 0 ]
            [ ! -f "$R/state/status" ]
            [ -f "$R/state/owned" ]
            [ ! -f "$R/run/stop" ] && [ ! -f "$R/run/owner.lock" ]
            if [ "$scenario" = reconcile-booting ]; then
                grep -q '^boot-reconcile:deferred$' "$WORK/stdout"
                export CASE=reconcile-finished
                sh "$WORK/current-runtime.sh" reconcile-boot
                grep -q '^disabled ' "$R/state/status"
                [ ! -f "$R/run/boot-id" ]
                [ "$(cat "$R/config/autostart-enabled")" = 1 ]
            fi
            ;;
        *)
            [ "$result" -ne 0 ]
            expected=$scenario
            case "$scenario" in
                missing-ipv4-nat|denied-nat|denied-ipv6-nat|broken-ipv6-nat) expected=inspect-firewall ;;
                occupied-nat) expected=reserved-chain ;;
                reconcile-reserved) expected=reserved-rules ;;
            esac
            [ "$scenario" != unsafe-tree ] || expected=safe-tree
            grep -q "root-runtime: step=$expected " "$WORK/stderr"
            ;;
    esac
    printf 'PASS cleanup: %s\n' "$scenario"
done
