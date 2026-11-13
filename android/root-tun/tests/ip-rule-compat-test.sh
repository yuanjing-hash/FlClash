#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=${FLCLASH_TEST_RUNTIME:-$TESTS/../../app/src/main/assets/root-tun/runtime.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flclash-ip-rule.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
printf '#!/bin/sh\ncat >/dev/null\n' > "$WORK/bin/iptables-restore"
cp "$WORK/bin/iptables-restore" "$WORK/bin/ip6tables-restore"
chmod +x "$WORK/bin/iptables-restore" "$WORK/bin/ip6tables-restore"
export PATH="$WORK/bin:$PATH"
R=$WORK/runtime STATE=$WORK/runtime/state BOOT=test-boot
mkdir -p "$R/config" "$STATE"
printf '1\n' > "$R/config/tun.enabled"
printf '1\n' > "$R/config/allow-bypass"
printf '10190\n' > "$R/config/bypass.uids"
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
ip() {
    printf '%s\n' "$*" >> "$WORK/commands"
    case "$*" in
        '-4 rule add pref 9011 table main suppress_prefixlength 0'|'-6 rule add pref 9011 table main suppress_prefixlength 0') return 0 ;;
        '-4 rule add pref 9009 iif lo table 2022'|'-6 rule add pref 9009 iif lo table 2022') return 0 ;;
        '-4 rule add pref 8990 fwmark '*|'-6 rule add pref 8990 fwmark '*)
            shift 6
            if [ "$#" = 3 ] && [ "$2" = goto ] && [ "$3" = 9011 ]; then return 0; fi
            echo 'Error: argument "ipproto" is wrong: Failed to parse rule type' >&2
            return 2
            ;;
        *) echo "Unsupported Android ip rule: $*" >&2; return 2 ;;
    esac
}
install_rules
! grep -Eq 'ipproto|dport|sport|uidrange' "$WORK/commands"
[ "$(wc -l < "$WORK/commands")" -eq 7 ]
grep -qx -- '-4 rule add pref 9009 iif lo table 2022' "$WORK/commands"
! grep -q -- '-6 rule add pref 9009' "$WORK/commands"
printf '1\n' > "$R/config/ipv6.enabled"
: > "$WORK/commands"
install_rules
[ "$(wc -l < "$WORK/commands")" -eq 8 ]
grep -qx -- '-6 rule add pref 9009 iif lo table 2022' "$WORK/commands"
echo 'PASS rules install with the Android ip grammar that rejected root.11'
echo 'PASS native TUN retains destination, protocol and UID routing ownership'
