#!/bin/sh
set -eu

root=${1:-$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)}
module=$root/core/Clash.Meta
patch=$root/core/patches/root-cache-path.patch
[ -f "$module/go.mod" ] || {
    echo 'Initialize the pinned core: git submodule update --init --recursive' >&2
    exit 1
}
applied() { git -C "$module" apply --reverse --check "$patch" >/dev/null 2>&1; }
applied && exit 0
git_dir=$(git -C "$root" rev-parse --absolute-git-dir)
lock=$git_dir/flclash-core-patch.lock
attempt=0
until mkdir "$lock" 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 100 ] || { echo "Core patch preparation is locked: $lock" >&2; exit 1; }
    sleep 0.1
done
trap 'rmdir "$lock" 2>/dev/null || true' EXIT HUP INT TERM
applied && exit 0
git -C "$module" apply --check "$patch" || {
    echo 'The Root cache feature patch does not match the checked-out mihomo core.' >&2
    exit 1
}
git -C "$module" apply "$patch"
applied
