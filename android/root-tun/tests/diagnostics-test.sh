#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
R=$WORK/runtime
export R FAKE_NET="$WORK/net" TMPDIR="$WORK" PATH="$WORK/bin:$PATH"
REAL_ID=$(command -v id)
export REAL_ID
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
printf '%s\n' "$TMPDIR" > "$FAKE_NET/nft-tmpdir"
yes rule | head -c 300000
NFT
cat > "$WORK/bin/id" <<'ID'
#!/bin/sh
if [ "$*" = '-u' ]; then echo "${DIAGNOSTIC_UID:-0}"; else exec "$REAL_ID" "$@"; fi
ID
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
grep -q 'nft exit=0 timeout=no truncated=yes bytes=98305 status=success' "$WORK/evidence"
[ "$(cat "$FAKE_NET/nft-tmpdir")" = "$R/tmp" ]
[ "$(stat -c %a "$R/tmp")" = 700 ]
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

sed '/^pids=/,$d' "$WORK/diagnostics.sh" > "$WORK/prologue.sh"
cat >> "$WORK/prologue.sh" <<'PROLOGUE'
printf '%s\n' "$D" > "$FAKE_NET/diagnostic-directory"
PROLOGUE
rmdir "$R/tmp"
sh "$WORK/prologue.sh"
[ "$(dirname "$(cat "$FAKE_NET/diagnostic-directory")")" = "$R/tmp" ]
[ "$(stat -c %a "$R/tmp")" = 700 ]
mkdir "$WORK/app-cache"
DIAGNOSTIC_UID=10000 TMPDIR="$WORK/app-cache" sh "$WORK/prologue.sh"
[ "$(dirname "$(cat "$FAKE_NET/diagnostic-directory")")" = "$WORK/app-cache" ]
echo 'PASS diagnostics: root prefers and creates runtime tmp with mode 0700; nonprivileged collection uses App cache'

sed '/^collect clock /,$d' "$WORK/diagnostics.sh" > "$WORK/bounded.sh"
cat >> "$WORK/bounded.sh" <<'BOUNDED'
collect exact 1 head -c 98304 /dev/zero
collect over 1 head -c 98305 /dev/zero
collect failure 1 sh -c 'head -c 300000 /dev/zero; exit 7'
collect slow 1 sleep 3
for collector_pid in $pids; do wait "$collector_pid"; done
grep -q '^exact exit=0 timeout=no truncated=no bytes=98304 status=success$' "$D/exact.manifest"
grep -q '^over exit=0 timeout=no truncated=yes bytes=98305 status=success$' "$D/over.manifest"
grep -q '^failure exit=7 timeout=no truncated=yes bytes=98305 status=failed$' "$D/failure.manifest"
grep -q '^slow exit=137 timeout=yes truncated=no ' "$D/slow.manifest"
for item in exact over failure; do
    [ "$(wc -c < "$D/$item.raw")" -le 98305 ]
    [ "$(wc -c < "$D/$item.txt")" -eq 98304 ]
done
BOUNDED
sh -eu "$WORK/bounded.sh" > "$WORK/bounded.log"
[ "$(find "$WORK" -name 'root-diagnostics.*' | wc -l)" -eq 0 ]
echo 'PASS diagnostics: output limit and sentinel bound disk usage; manifest distinguishes exact size, truncation, command failure and timeout'
