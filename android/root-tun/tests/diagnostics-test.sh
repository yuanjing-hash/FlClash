#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
R=$WORK/runtime
export R FAKE_NET="$WORK/net" TMPDIR="$WORK" PATH="$WORK/bin:$PATH"
mkdir -p "$R/logs" "$R/tmp" "$R/config" "$R/state" "$R/scripts" "$WORK/net" "$WORK/bin" "$WORK/service.d"
printf '%s\n' 'stage=user_unlocked elapsedMs=1234' > "$R/logs/boot.log"
printf '%s\n' 'header: 85 83 75 127 3 0 0 0' > "$R/logs/allowlist-denied.txt"
printf '%s\n' 'notification code=AUTOSTART_FAILED exit=0' > "$R/logs/notification-last.txt"
printf '%s\n' 10000 > "$R/config/app.uid"
printf '%s\n' kernelsu > "$R/config/root.manager"
for stub in ip iptables-save ip6tables-save settings nc pm; do ln -s "$TESTS/network-stub.sh" "$WORK/bin/$stub"; done
cat > "$WORK/bin/am" <<'AM'
#!/bin/sh
sleep 4
AM
cat > "$WORK/bin/nft" <<'NFT'
#!/bin/sh
yes rule | head -c 180000
NFT
cat > "$WORK/bin/su" <<'SU'
#!/bin/sh
echo 'FAIL diagnostics invoked su' >> "$FAKE_NET/su-called"
exit 1
SU
cat > "$WORK/bin/getprop" <<'PROP'
#!/bin/sh
echo diagnostic-property
PROP
chmod +x "$WORK/bin/"*
sed -e "s|^R=/data/adb/flclash-root$|R=$R|" -e "s|/data/adb/service.d|$WORK/service.d|g" \
    "$TESTS/../../app/src/main/assets/root-tun/diagnostics.sh" > "$WORK/diagnostics.sh"
cp "$TESTS/../../app/src/main/assets/root-tun/authorization.sh" "$R/scripts/authorization.sh"
started=$(date +%s)
sh "$WORK/diagnostics.sh" > "$WORK/evidence"
[ "$(($(date +%s) - started))" -lt 15 ]
[ ! -f "$FAKE_NET/su-called" ]
grep -q 'nft exit=.*truncated=yes' "$WORK/evidence"
grep -q 'stage=user_unlocked elapsedMs=1234' "$WORK/evidence"
grep -q 'header: 85 83 75 127' "$WORK/evidence"
grep -q 'notification code=AUTOSTART_FAILED exit=0' "$WORK/evidence"
grep -q 'am-exit=137' "$WORK/evidence"
for item in clock boot-state tools boot-evidence auth-data package device grep processes directories runtime-state notifications ipv4 ipv6 iptables ip6tables nft selinux connectivity restore-diff baseline logs; do
    grep -q "^$item exit=" "$WORK/evidence"
done
[ "$(wc -c < "$WORK/evidence")" -lt 4194304 ]
[ "$(find "$WORK" -name 'root-diagnostics.*' | wc -l)" -eq 0 ]
echo 'PASS diagnostics: all items manifested, am timeout and nft truncation recorded; boot/revocation evidence retained without su'
