#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=${FLCLASH_TEST_RUNTIME:-$TESTS/../../app/src/main/assets/root-tun/runtime.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flclash-options.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
printf '#!/bin/sh\ncat > "$FLCLASH_TEST_WORK/filter4"\n' > "$WORK/bin/iptables-restore"
printf '#!/bin/sh\ncat > "$FLCLASH_TEST_WORK/filter6"\n' > "$WORK/bin/ip6tables-restore"
chmod +x "$WORK/bin/iptables-restore" "$WORK/bin/ip6tables-restore"
export FLCLASH_TEST_WORK="$WORK" PATH="$WORK/bin:$PATH"
R=$WORK/runtime
mkdir -p "$R/config"
sed -n '/^configure_routes() {/,/^configure_system_proxy() {/p' "$SOURCE" | sed '$d' > "$WORK/functions.sh"
. "$WORK/functions.sh"
ip() {
    printf '%s\n' "$*" >> "$WORK/routes"
    case "$*" in *' ipproto '*|*' dport '*|*' uidrange '*) echo 'Unsupported Android ip rule selector' >&2; return 2 ;; esac
    case "$*" in '-4 route show table 2022') echo '8.0.0.0/8 dev flcrtun0';; esac
}
iptables() { printf '%s\n' "$*" >> "$WORK/guard4"; }
ip6tables() { printf '%s\n' "$*" >> "$WORK/guard6"; }
printf '1\n' > "$R/config/tun.enabled"
printf '1\n' > "$R/config/ipv6.enabled"
printf '1\n' > "$R/config/allow-bypass"
printf '10200\n' > "$R/config/bypass.uids"
printf '8.0.0.0/8\n198.18.0.0/30\n' > "$R/config/routes4"
printf '2001:db8::/32\n' > "$R/config/routes6"
configure_routes
configure_guard iptables 4
configure_guard ip6tables 6
grep -q -- '-4 route show table 2022' "$WORK/routes"
! grep -q -- 'route replace\|rule add' "$WORK/routes"
grep -q -- '--mark 0x20000/0xa0000 -j RETURN' "$WORK/guard4"
! grep -q -- '--mark 0x10000' "$WORK/guard4"
grep -q -- '--uid-owner 10200 -j RETURN' "$WORK/guard4"
grep -q -- '-d 8.0.0.0/8 ! -o flcrtun0 -j REJECT' "$WORK/guard4"
! grep -qx -- '-w 1 -A FCR_OUTPUT ! -o flcrtun0 -j REJECT' "$WORK/guard4"
grep -q -- '-d 2001:db8::/32 ! -o flcrtun0 -j REJECT' "$WORK/guard6"
echo 'PASS UI routes, applications and bypass are honored by both families'
printf '0\n' > "$R/config/ipv6.enabled"
printf '0\n' > "$R/config/allow-bypass"
: > "$WORK/guard6"
configure_guard ip6tables 6
grep -qx -- '-w 1 -A FCR_OUTPUT -j REJECT' "$WORK/guard6"
! grep -q -- '--mark 0x20000' "$WORK/guard6"
echo 'PASS disabled IPv6 and disabled explicit bypass remain disabled'
printf '0\n' > "$R/config/tun.enabled"
: > "$WORK/routes"
configure_routes
[ ! -s "$WORK/routes" ]
echo 'PASS disabled VPN does not install capture routes'

sed -n '/^install_rules() {/,/^configure_routes() {/p' "$SOURCE" | sed '$d' > "$WORK/rules.sh"
. "$WORK/rules.sh"
owns() { return 0; }
vacant() { return 0; }
baseline() { return 0; }
sync() { :; }
configure_system_proxy() { :; }
update_private_dns() { :; }
STATE=$R/state
BOOT=test-boot
mkdir -p "$STATE"
printf '1\n' > "$R/config/tun.enabled"
printf '1\n' > "$R/config/allow-bypass"
: > "$WORK/routes"
install_rules
! grep -q -- 'pref 8992' "$WORK/routes"
grep -q -- '-A FCR_OUTPUT -d 8.0.0.0/8 ! -o flcrtun0 -j REJECT' "$WORK/filter4"
grep -q -- '-A FCR_OUTPUT -j REJECT' "$WORK/filter6"
grep -q '^COMMIT$' "$WORK/filter4"
grep -q -- '-4 rule add pref 8990 fwmark 0x20000/0xa0000 goto 9011' "$WORK/routes"
! grep -q -- 'fwmark 0x10000' "$WORK/routes"
! grep -q -- 'uidrange\|pref 8991' "$WORK/routes"
bypass_selector=$(sed -n 's/^-4 rule add pref 8990 fwmark \([^ ]*\) goto 9011$/\1/p' "$WORK/routes" | grep -v '^0x40000000')
bypass_value=${bypass_selector%/*}
bypass_mask=${bypass_selector#*/}
for mark in 0x100e5 0x100e9 0x10067; do
    [ $((mark & bypass_mask)) -ne $((bypass_value)) ]
done
[ $((0x200e5 & bypass_mask)) -eq $((bypass_value)) ]
[ $((0x600e5 & bypass_mask)) -eq $((bypass_value)) ]
echo 'PASS explicit Wi-Fi and mobile bindings stay captured; only VPN-protected sockets may bypass'
route_target() {
    packet_mark=$1
    while IFS= read -r command; do
        case "$command" in '-4 rule add pref 8990 fwmark '*) ;; *) continue ;; esac
        set -- $command
        shift 6
        selector=$1
        shift
        [ $((packet_mark & ${selector#*/})) -eq $(( ${selector%/*} )) ] || continue
        printf '%s\n' "$2"
        return
    done < "$WORK/routes"
    echo 9000
}
for mark in 0xf01e7 0xf01e8; do
    for protocol in udp tcp; do
        [ "$(route_target "$mark" "$protocol" 53)" = 9000 ]
    done
    [ "$(route_target "$mark" tcp 443)" = 9000 ]
done
[ "$(route_target 0x201e7 udp 53)" = 9011 ]
[ "$(route_target 0x201e7 tcp 443)" = 9011 ]
[ "$(route_target 0x400f01e7 udp 53)" = 9011 ]
echo 'PASS netd DNS reaches native capture without bypassing app filters or looping Core sockets'
echo 'PASS native Core owns routes; the startup guard is published in one batch per family'
