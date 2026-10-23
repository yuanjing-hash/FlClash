#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=$TESTS/../../app/src/main/assets/root-tun/runtime.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export FAKE_NET="$WORK/net"
export PATH="$WORK/bin:$PATH"
mkdir -p "$FAKE_NET" "$WORK/bin" "$WORK/data" "$WORK/service.d"
for stub in pm log ip iptables ip6tables iptables-save ip6tables-save settings; do
    ln -s "$TESTS/network-stub.sh" "$WORK/bin/$stub"
done
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" \
    -e '/^export PATH=/d' -e '/^safe_tree || exit 1/,$d' \
    -e "s|/data/data/com.follow.clash.root|$WORK/data/com.follow.clash.root|g" \
    -e "s|/data/adb/service.d|$WORK/service.d|g" "$SOURCE" > "$WORK/functions.sh"
# shellcheck source=/dev/null
. "$WORK/functions.sh"
mkdir -p "$STATE" "$RUN" "$R/logs"
IDENTITY="$$ $(ticks "$$") $BOOT"
export IDENTITY
[ "$(package_status)" = present ]
echo prefix > "$FAKE_NET/package"
[ "$(package_status)" = absent ]
echo 'PASS exact root package; similarly named package does not count'
for result in fail timeout; do
    echo "$result" > "$FAKE_NET/package"
    [ "$(package_status)" = unknown ]
done
echo 'PASS pm errors and timeouts remain unknown'
echo android-absent > "$FAKE_NET/package"
[ "$(package_status)" = absent ]
echo binder-failure > "$FAKE_NET/package"
[ "$(package_status)" = unknown ]
echo 'PASS Android pm path exit 1 requires a successful exact list query; binder failure remains unknown'
echo absent > "$FAKE_NET/package"
mkdir "$WORK/data/com.follow.clash.root"
[ "$(package_status)" = present ]
rmdir "$WORK/data/com.follow.clash.root"
echo 'PASS retained data from uninstall -k prevents deletion'
missing_count=0
if check_uninstall; then exit 1; fi
[ -d "$R" ]
echo fail > "$FAKE_NET/package"
if check_uninstall; then exit 1; fi
[ "$missing_count" -eq 0 ]
echo absent > "$FAKE_NET/package"
if check_uninstall; then exit 1; fi
printf '%s\n' '#!/system/bin/sh' '# flclash-root service.d v1' > "$WORK/service.d/flclash-root.sh"
printf foreign > "$WORK/service.d/foreign.sh"
check_uninstall
[ ! -e "$R" ] && [ ! -e "$WORK/service.d/flclash-root.sh" ]
[ -f "$WORK/service.d/foreign.sh" ]
grep -q 'cleanup complete' "$FAKE_NET/logcat"
echo 'PASS two consecutive absences clean runtime and only owned entry; logcat retains evidence'
