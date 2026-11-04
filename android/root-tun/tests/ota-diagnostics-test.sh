#!/bin/sh
set -eu
TESTS=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flclash-ota.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
REAL_READLINK=$(command -v readlink)
export REAL_READLINK
cat > "$WORK/bin/pidof" <<'PIDOF'
#!/bin/sh
[ "$SCENARIO" != fd ] || echo 311
exit 0
PIDOF
cat > "$WORK/bin/readlink" <<'READLINK'
#!/bin/sh
case "$1" in */proc/311/fd/3) printf '%s\n' "$OTA_FD_TARGET" ;; *) exec "$REAL_READLINK" "$@" ;; esac
READLINK
cat > "$WORK/bin/logcat" <<'LOGCAT'
#!/bin/sh
[ "$SCENARIO" != oem ] || echo '11-04 17:48:00 MiuiUpdater: timestamp verification failed ErrorCode=51'
exit 0
LOGCAT
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"
for scenario in empty extensionless fd oem budget binary; do
    case_root=$WORK/$scenario
    mkdir -p "$case_root/logs" "$case_root/logs2" "$case_root/proc" "$case_root/tmp"
    export SCENARIO=$scenario D=$case_root/tmp
    case "$scenario" in
        extensionless) echo 'ErrorCode::kPayloadTimestampError (51) old=1792509111 new=1792500000' > "$case_root/logs/update_engine.20261104-174000" ;;
        fd)
            mkdir -p "$case_root/proc/311/fd"
            printf '/system/bin/update_engine\000--logtofile\000' > "$case_root/proc/311/cmdline"
            echo 'ErrorCode::kPayloadTimestampError (51) partition=vendor' > "$case_root/proc/311/fd/3"
            export OTA_FD_TARGET=$case_root/hidden/update_engine.20261104-174000
            ;;
        budget)
            for directory in logs logs2; do
                for index in 1 2 3; do
                    head -c 1048576 /dev/zero > "$case_root/$directory/update_engine.20261104-17400$index"
                    printf '\nErrorCode=51 bounded evidence\n' >> "$case_root/$directory/update_engine.20261104-17400$index"
                done
            done
            ;;
        binary) echo 'must-not-read-payload' > "$case_root/logs/update_engine.bin" ;;
    esac
    sed -e "s|^PROC=/proc$|PROC='$case_root/proc'|" \
        -e "s|^LOG_ROOTS=.*|LOG_ROOTS='$case_root/logs $case_root/logs2'|" \
        "$TESTS/../../app/src/main/assets/root-tun/ota-diagnostics.sh" > "$case_root/collector.sh"
    result=0
    sh "$case_root/collector.sh" > "$case_root/evidence" 2>&1 || result=$?
    case "$scenario" in
        empty|binary)
            [ "$result" -eq 3 ]
            grep -q 'NO_OTA_LOG_SOURCES' "$case_root/evidence"
            ! grep -q must-not-read-payload "$case_root/evidence"
            ;;
        extensionless|fd)
            [ "$result" -eq 0 ]
            grep -q 'kPayloadTimestampError (51)' "$case_root/evidence"
            grep -q 'ota-sources=1' "$case_root/evidence"
            ;;
        oem)
            [ "$result" -eq 0 ]
            grep -q 'MiuiUpdater: timestamp verification failed ErrorCode=51' "$case_root/evidence"
            ;;
        budget)
            [ "$result" -eq 0 ]
            grep -q 'ota-sources=5' "$case_root/evidence"
            [ "$(wc -c < "$case_root/evidence")" -lt 98304 ]
            for raw in "$D"/ota-source.*; do [ "$(wc -c < "$raw")" -le 524288 ]; done
            ;;
    esac
    echo "PASS OTA collector: $scenario"
done
