#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=${FLCLASH_TEST_RUNTIME:-$TESTS/../../app/src/main/assets/root-tun/runtime.sh}
if [ "${1:-}" != --netns ]; then
    if [ "$(uname -s)" != Linux ]; then
        echo 'SKIP kernel routing regression requires Linux network namespaces'
        exit 0
    fi
    parent_namespace=$(readlink /proc/self/ns/net)
    if [ "$(id -u)" = 0 ]; then
        exec unshare -n -- sh "$0" --netns "$SOURCE" "$parent_namespace"
    fi
    exec sudo -n unshare -n -- sh "$0" --netns "$SOURCE" "$parent_namespace"
fi
SOURCE=$2
[ "$(readlink /proc/self/ns/net)" != "$3" ] || exit 1
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flclash-kernel-routing.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
R=$WORK/runtime STATE=$WORK/runtime/state BOOT=test-boot
mkdir -p "$R/config" "$STATE" "$WORK/bin"
printf '#!/bin/sh\ncat >/dev/null\n' > "$WORK/bin/iptables-restore"
cp "$WORK/bin/iptables-restore" "$WORK/bin/ip6tables-restore"
chmod +x "$WORK/bin/iptables-restore" "$WORK/bin/ip6tables-restore"
PATH="$WORK/bin:$PATH"
export PATH
printf '1\n' > "$R/config/tun.enabled"
printf '1\n' > "$R/config/ipv6.enabled"
printf '1\n' > "$R/config/allow-bypass"
sed -n '/^install_rules() {/,/^configure_routes() {/p' "$SOURCE" | sed '$d' > "$WORK/functions.sh"
. "$WORK/functions.sh"
owns() { return 0; }
vacant() { return 0; }
baseline() { return 0; }
sync() { :; }
configure_system_proxy() { :; }
update_private_dns() { :; }
emit_filter() { echo COMMIT; }
iptables() { :; }
ip6tables() { :; }

ip link set lo up
for name in wlan0 rmnet_data3 flcrtun0 shared0; do
    ip link add "$name" type dummy
    ip link set "$name" up
done
ip -4 address add 192.168.2.10/24 dev wlan0
ip -4 address add 10.0.0.2/32 dev rmnet_data3
ip -4 address add 198.18.0.1/30 dev flcrtun0
ip -4 address add 10.1.0.1/24 dev shared0
printf '1\n' > /proc/sys/net/ipv4/ip_forward
ip -6 address add 2001:db8:1::154/64 dev wlan0 nodad
ip -6 address add 2001:db8:2::181/64 dev rmnet_data3 nodad
ip -6 address add fdfe:dcba:9876::1/126 dev flcrtun0 nodad
ip -4 route add default dev wlan0
ip -6 route add default dev wlan0
ip -4 route add 203.0.113.0/24 dev flcrtun0 table 2022
ip -4 route add 192.0.2.53/32 dev flcrtun0 table 2022
ip -6 route add 2001:db8:100::/64 dev flcrtun0 table 2022
for family in -4 -6; do
    ip "$family" rule add pref 8991 uidrange 10346-10346 goto 9011
    ip "$family" rule add pref 9000 uidrange 10346-10346 goto 9010
    ip "$family" rule add pref 9001 iif lo goto 9003
    ip "$family" rule add pref 9002 goto 9010
    # Empty table 2023 makes goto targets behave like native NOP rules.
    ip "$family" rule add pref 9003 table 2023
    ip "$family" rule add pref 9004 iif flcrtun0 goto 9010
    ip "$family" rule add pref 9005 not iif lo table 2022
    ip "$family" rule add pref 9010 table 2023
done
ip -4 rule add pref 9005 from 0.0.0.0/32 iif lo table 2022
ip -4 rule add pref 9005 from 198.18.0.0/30 iif lo table 2022
ip -6 rule add pref 9005 from ::/128 iif lo table 2022
ip -6 rule add pref 9005 from fdfe:dcba:9876::/126 iif lo table 2022

assert_device() {
    expected=$1
    shift
    route=$(ip "$@")
    printf '%s\n' "$route" | grep -q "dev $expected " || {
        echo "Expected $expected for ip $*, got $route" >&2
        exit 1
    }
}
assert_device wlan0 -4 route get 203.0.113.1 from 192.168.2.10 uid 10527
assert_device wlan0 -6 route get 2001:db8:100::10 from 2001:db8:1::154 uid 10527
echo 'PASS reproduced native source-bound capture gap in the Linux kernel'

install_rules
assert_device flcrtun0 -4 route get 203.0.113.1 from 192.168.2.10 uid 10527
assert_device flcrtun0 -6 route get 2001:db8:100::10 from 2001:db8:1::154 uid 10527
ip -4 route replace default dev rmnet_data3
ip -6 route replace default dev rmnet_data3
assert_device flcrtun0 -4 route get 203.0.113.1 from 10.0.0.2 uid 10527
assert_device flcrtun0 -6 route get 2001:db8:100::10 from 2001:db8:2::181 uid 10527
assert_device rmnet_data3 -4 route get 203.0.113.1 from 10.0.0.2 uid 10346
assert_device rmnet_data3 -6 route get 2001:db8:100::10 from 2001:db8:2::181 uid 10346
assert_device rmnet_data3 -4 route get 203.0.113.1 from 10.0.0.2 mark 0x40000000 uid 0
assert_device rmnet_data3 -4 route get 203.0.113.1 from 10.0.0.2 mark 0x20170 uid 10527
assert_device flcrtun0 -4 route get 203.0.113.1 from 10.0.0.2 mark 0x10170 uid 10527
assert_device flcrtun0 -4 route get 192.0.2.53 from 10.0.0.2 mark 0xf0170 uid 1051
assert_device rmnet_data3 -4 route get 192.0.2.53 from 10.0.0.2 mark 0xf0170 uid 10346
assert_device wlan0 -4 route get 192.168.2.1 from 10.0.0.2 uid 10527
assert_device rmnet_data3 -4 route get 203.0.113.1 from 10.1.0.2 iif shared0
echo 'PASS Wi-Fi and cellular source binding follows application and protected-socket policy'

ip -6 rule delete pref 9009
ip -6 rule add pref 9000 type unreachable
if ip -6 route get 2001:db8:100::10 from 2001:db8:2::181 uid 10527 >/dev/null 2>&1; then
    echo 'Disabled IPv6 escaped the capture policy' >&2
    exit 1
fi
assert_device rmnet_data3 -6 route get 2001:db8:100::10 from 2001:db8:2::181 uid 10346
echo 'PASS disabled IPv6 remains blocked for captured apps while excluded apps keep native routing'
