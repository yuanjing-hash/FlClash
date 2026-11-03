#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" -e '/^export PATH=/d' \
    -e '/^safe_tree || exit 1/,$d' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/functions.sh"
# shellcheck source=/dev/null
. "$WORK/functions.sh"
mkdir -p "$WORK/bin" "$R/logs"
export PATH="$WORK/bin:$PATH" NOTIFICATION_CALLS="$WORK/calls"
cat > "$WORK/bin/cmd" <<'CMD'
#!/bin/sh
printf '%s\n' "$*" >> "$NOTIFICATION_CALLS"
if [ -f "$NOTIFICATION_CALLS.fail" ]; then echo 'notification service unavailable' >&2; exit 7; fi
CMD
chmod +x "$WORK/bin/cmd"
for code in AUTOSTART_FAILED ROOT_PERMISSION_REVOKED AUTOSTART_ROOT_REVOKED CLEANUP_FAILED; do
    post_notification "$code"
    grep -q "($code)" "$WORK/calls"
    grep -q "code=$code exit=0" "$R/logs/notification-last.txt"
done
grep -q '开机自启未成功（网络未就绪或配置不可读），网络保持直连。 (AUTOSTART_FAILED)' "$WORK/calls"
grep -q 'root 授权已被撤销，Root TUN 已停止，网络已恢复直连。 (ROOT_PERMISSION_REVOKED)' "$WORK/calls"
grep -q '状态提醒' "$WORK/calls"
touch "$NOTIFICATION_CALLS.fail"
post_notification AUTOSTART_FAILED
grep -q 'code=AUTOSTART_FAILED exit=7' "$R/logs/notification-last.txt"
grep -q 'notification service unavailable' "$R/logs/notification-last.txt"
echo 'PASS appendix B Chinese notifications retain codes, command exit and stderr on success/failure'
