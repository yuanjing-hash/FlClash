#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cgroups" "$WORK/runtime/logs"
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" -e '/^export PATH=/d' \
    -e 's|^BOOT=$(cat /proc/sys/kernel/random/boot_id)$|BOOT=test-boot|' \
    -e "s|/acct/cgroup.procs|$WORK/cgroups/acct|g" \
    -e "s|/dev/cg2_bpf/cgroup.procs|$WORK/cgroups/bpf|g" \
    -e "s|/sys/fs/cgroup/cgroup.procs|$WORK/cgroups/unified|g" \
    -e "s|/dev/memcg/apps/cgroup.procs|$WORK/cgroups/memory|g" \
    -e '/^safe_tree || exit 1/,$d' "$TESTS/../../app/src/main/assets/root-tun/runtime.sh" > "$WORK/functions.sh"
. "$WORK/functions.sh"
boot_seconds() { echo 1; }
for group in acct bpf unified memory; do
    printf 'unrelated-pid\n' > "$WORK/cgroups/$group"
done
detach_cgroups supervise
for group in acct bpf unified memory; do
    [ "$(cat "$WORK/cgroups/$group")" = "$(printf 'unrelated-pid\n%s' "$$")" ]
done
grep -q "detached role=supervise pid=$$ cgroups=" "$R/logs/launch.log"
echo 'PASS detached workers move only their own PID and preserve existing group members'
rm "$WORK/cgroups/bpf" "$WORK/cgroups/memory"
ln -s /proc/version "$WORK/cgroups/memory"
detach_cgroups watchdog
grep -q "cgroup detach failed path=$WORK/cgroups/memory pid=$$" "$R/logs/launch.log"
grep -q "detached role=watchdog pid=$$" "$R/logs/launch.log"
echo 'PASS missing or inaccessible cgroups retain diagnostics without aborting the root worker'
