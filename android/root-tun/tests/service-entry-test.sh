#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/service.d"
sed -e "s|^R=/data/adb/flclash-root$|R=$WORK/runtime|" \
    -e "s|/data/adb/service.d|$WORK/service.d|g" \
    -e 's|/system/bin/sh|/bin/sh|g' \
    -e 's/ = 0 ]/ = '"$(id -u)"' ]/' \
    "$TESTS/../../app/src/main/assets/root-tun/service.d.sh" > "$WORK/entry.sh"
for version in 1 2; do
    printf '# flclash-root service.d v%s\n' "$version" > "$WORK/service.d/flclash-root.sh"
    sh "$WORK/entry.sh"
    [ ! -e "$WORK/service.d/flclash-root.sh" ]
done
printf '%s\n' '# foreign version v3' > "$WORK/service.d/flclash-root.sh"
sh "$WORK/entry.sh"
[ -f "$WORK/service.d/flclash-root.sh" ]
printf foreign > "$WORK/service.d/foreign.sh"
[ -f "$WORK/service.d/foreign.sh" ]
echo 'PASS missing runtime removes only recognized v1/v2 entry; unknown marker remains'
rm -f "$WORK/service.d/flclash-root.sh"
ln -s "$WORK/service.d/foreign.sh" "$WORK/service.d/flclash-root.sh"
sh "$WORK/entry.sh"
[ -L "$WORK/service.d/flclash-root.sh" ]
[ "$(cat "$WORK/service.d/foreign.sh")" = foreign ]
echo 'PASS symlink entry does not alter foreign file'
