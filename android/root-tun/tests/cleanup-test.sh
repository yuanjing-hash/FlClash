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
alive() { return 1; }
stat() {
    if [ "$*" = "-c %u $R" ]; then printf '0\n'; else command stat "$@"; fi
}
ip() {
    case "$*" in
        '-4 rule show'|'-6 rule show')
            [ "$CASE" != inspect-rules ] || { echo 'Operation not permitted' >&2; return 2; }
            printf '0: from all lookup local\n10000: from all lookup 99\n32000: from all unreachable\n'
            [ "$CASE" != reserved-rules ] || echo '9000: from all lookup 1234'
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
            esac
            ;;
        '-w 1 -t nat -S mihomo-output') return 1 ;;
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
for scenario in incomplete stale-script missing-table missing-ipv6-nat previous-boot owned reserved-rules inspect-rules inspect-routes reserved-table reserved-link reserved-chain inspect-firewall missing-ipv4-nat denied-nat denied-ipv6-nat broken-ipv6-nat occupied-nat unsafe-tree; do
    R=$WORK/$scenario
    mkdir -p "$R"
    if [ "$scenario" = stale-script ]; then
        mkdir -p "$R/scripts"
        printf 'echo stale-script-was-executed >&2\nexit 91\n' > "$R/scripts/runtime.sh"
    fi
    case "$scenario" in
        previous-boot|owned)
            mkdir -p "$R/state"
            printf 'reserved\n' > "$R/state/owned"
            if [ "$scenario" = previous-boot ]; then
                printf 'previous-boot\n' > "$R/state/owned.boot"
            else
                printf 'test-boot\n' > "$R/state/owned.boot"
                for item in -4.rules -6.rules; do
                    printf '0: from all lookup local\n10000: from all lookup 99\n32000: from all unreachable\n' > "$R/state/baseline.$item"
                done
                for item in -4.routes -6.routes; do : > "$R/state/baseline.$item"; done
                for item in iptables ip6tables; do
                    printf '*filter\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$R/state/baseline.$item"
                done
            fi
            ;;
    esac
    sed -e "s|^R=/data/adb/flclash-root$|R='$R'|" \
        -e 's|^BOOT=.*|BOOT=test-boot|' -e '/^export PATH=/d' \
        -e "/^safe_tree || exit 1/i\\
. '$WORK/stubs.sh'" "$SOURCE" > "$WORK/current-runtime.sh"
    export CASE=$scenario
    if [ "$scenario" = unsafe-tree ]; then
        sed "s|\[ ! -L \"\$R\" \]|[ false = true ]|" "$WORK/current-runtime.sh" > "$WORK/unsafe-runtime.sh"
        cp "$WORK/unsafe-runtime.sh" "$WORK/current-runtime.sh"
    fi
    result=0
    sh "$WORK/current-runtime.sh" cleanup > "$WORK/stdout" 2> "$WORK/stderr" || result=$?
    case "$scenario" in
        incomplete|stale-script|missing-table|missing-ipv6-nat|previous-boot|owned)
            if [ "$result" -ne 0 ]; then cat "$WORK/stderr" >&2; exit 1; fi
            grep -q '^disabled ' "$R/state/status"
            [ ! -e "$R/run/owner.lock" ] && [ ! -e "$R/run/control.lock" ]
            [ ! -f "$R/state/owned" ] && [ ! -f "$R/state/owned.boot" ]
            [ ! -s "$WORK/stderr" ]
            ;;
        *)
            [ "$result" -ne 0 ]
            expected=$scenario
            case "$scenario" in
                missing-ipv4-nat|denied-nat|denied-ipv6-nat|broken-ipv6-nat) expected=inspect-firewall ;;
                occupied-nat) expected=reserved-chain ;;
            esac
            [ "$scenario" != unsafe-tree ] || expected=safe-tree
            grep -q "root-runtime: step=$expected " "$WORK/stderr"
            ;;
    esac
    printf 'PASS cleanup: %s\n' "$scenario"
done
