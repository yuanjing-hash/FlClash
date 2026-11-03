#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
SOURCE=$TESTS/../../app/src/main/assets/root-tun/runtime.sh
TEST_TMP=${TMPDIR:-/tmp}
WORK=$(mktemp -d "$TEST_TMP/flclash-tun-device.XXXXXX")
case "$WORK" in "$TEST_TMP"/flclash-tun-device.*) ;; *) exit 1 ;; esac
trap 'rm -rf "$WORK"' EXIT
for layout in android legacy missing; do
    (
        trap - EXIT
        R=$WORK/$layout
        mkdir -p "$R/run" "$R/state" "$R/logs"
        android_device=$R/missing
        legacy_device=$R/missing
        case "$layout" in
            android) android_device=/dev/null ;;
            legacy) legacy_device=/dev/null ;;
        esac
        sed -e "s|^R=/data/adb/flclash-root$|R=$R|" \
            -e 's|^BOOT=.*|BOOT=test-boot|' -e '/^export PATH=/d' \
            -e '/^safe_tree || exit 1/,$d' \
            -e "s|/dev/net/tun|$legacy_device|g" -e "s|/dev/tun|$android_device|g" \
            "$SOURCE" > "$R/functions.sh"
        . "$R/functions.sh"
        IDENTITY='1234 1 test-boot'
        claim_owner() { generation=1; }
        owns() { return 1; }
        publish() { printf '%s %s\n' "$1" "${2:--}" >> "$R/events"; }
        heartbeat() { :; }
        ensure_watchdog() { :; }
        fresh() { return 0; }
        unlock() { :; }
        cleanup() { return 0; }
        install_rules() { touch "$R/rules"; }
        launch_core() { touch "$R/launched"; return 1; }
        supervise
        if [ "$layout" = missing ]; then
            grep -q '^failed TUN_DEVICE_UNSUPPORTED$' "$R/events"
            [ ! -f "$R/rules" ] && [ ! -f "$R/launched" ]
        else
            [ -f "$R/rules" ] && [ -f "$R/launched" ]
            if grep -q TUN_DEVICE_UNSUPPORTED "$R/events"; then exit 1; fi
        fi
        printf 'PASS TUN device layout: %s\n' "$layout"
    )
done
