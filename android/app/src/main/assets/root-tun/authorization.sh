#!/system/bin/sh

manager_authorization() {
    auth_uid=${1:-$(cat "$R/config/app.uid" 2>/dev/null)}
    case "$auth_uid" in ''|*[!0-9]*) echo unknown; return ;; esac
    case "${2:-$(cat "$R/config/root.manager" 2>/dev/null)}" in
        kernelsu) kernelsu_authorization ;;
        magisk)
            magisk_bin=$(command -v magisk) || magisk_bin=''
            if [ -z "$magisk_bin" ]; then
                for binary in /data/adb/magisk/magisk /sbin/magisk /debug_ramdisk/magisk; do
                    if [ -x "$binary" ]; then magisk_bin=$binary; break; fi
                done
            fi
            [ -n "$magisk_bin" ] || { echo unknown; return; }
            policy=$(timeout -s KILL 1 "$magisk_bin" --sqlite "SELECT policy,until FROM policies WHERE uid=$auth_uid;" 2>&1) || { echo unknown; return; }
            if [ -z "$policy" ]; then echo denied; return; fi
            printf '%s\n' "$policy" | awk -F '[=|]' -v now="$(date +%s)" '
                /^policy=[012][|]until=[0-9]+$/ {
                    valid++; allowed=($2 == 2 && ($4 == 0 || $4 > now))
                }
                END { if (valid != 1) print "unknown"; else print allowed ? "granted" : "denied" }'
            ;;
        apatch)
            [ -r /data/adb/ap/package_config ] || { echo unknown; return; }
            awk -F, -v uid="$auth_uid" '
                NR == 1 && $0 == "pkg,exclude,allow,uid,to_uid,sctx" { header=1; next }
                NF != 6 || /["\r]/ || $2 !~ /^[01]$/ || $3 !~ /^[01]$/ || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { bad=1; next }
                { rows++ }
                $1 == "com.follow.clash.root" && $4 == uid { found++; allowed=$3 }
                END {
                    if (bad || (!header && !rows) || found > 1) print "unknown";
                    else if (found == 1) print allowed == 1 ? "granted" : "denied";
                    else print "denied"
                }' /data/adb/ap/package_config
            ;;
        *) echo unknown ;;
    esac
}

kernelsu_authorization() {
    allowlist=/data/adb/ksu/.allowlist
    allow_size=$(stat -c %s "$allowlist" 2>/dev/null) || { echo unknown; return; }
    [ "$allow_size" -ge 8 ] && [ "$allow_size" -le 4194304 ] || { echo unknown; return; }
    allow_bytes=${TMPDIR:-$R/tmp}/allowlist.$$.bytes
    od -An -v -tu1 "$allowlist" > "$allow_bytes" 2>/dev/null || { echo unknown; return; }
    # KernelSU disk ABI: v2/v3 records are 776 bytes; v4 adds root_profile.flags.
    awk -v uid="$auth_uid" -v size="$allow_size" '
        function u32(i) { return b[i]+256*b[i+1]+65536*b[i+2]+16777216*b[i+3] }
        { for (i=1;i<=NF;i++) b[n++]=$i }
        END {
            v=u32(4); stride=v == 4 ? 784 : 776;
            if (n != size || b[0] != 85 || b[1] != 83 || b[2] != 75 || b[3] != 127 ||
                v < 2 || v > 4 || (n-8)%stride != 0) { print "unknown"; exit }
            for (p=8;p<n;p+=stride) {
                if (u32(p) != v || b[p+264] > 1) { print "unknown"; exit }
                key="";
                for (k=4;k<260 && b[p+k]!=0;k++) key=key sprintf("%c", b[p+k]);
                if (key == "com.follow.clash.root" && u32(p+260) == uid) {
                    found++; allowed=b[p+264]
                }
            }
            if (found > 1) print "unknown"; else print found == 1 && allowed ? "granted" : "denied"
        }' "$allow_bytes"
    rm -f "$allow_bytes"
}

app_authorization() {
    [ -r "$R/config/app-auth" ] || { echo unknown; return; }
    read -r auth_port auth_token < "$R/config/app-auth"
    case "$auth_port" in ''|*[!0-9]*) echo unknown; return ;; esac
    auth_nonce=$(cat /proc/sys/kernel/random/uuid)
    runtime_status=$(cat "$STATE/status" 2>/dev/null) || runtime_status=disabled
    runtime_status="$runtime_status|auth:$(cat "$STATE/auth-status" 2>/dev/null)|dns:$(cat "$STATE/private-dns" 2>/dev/null)"
    if own_entry; then runtime_status="$runtime_status|autostart:yes"; else runtime_status="$runtime_status|autostart:no"; fi
    if [ -s "$R/logs/restore-diff.txt" ]; then runtime_status="$runtime_status|restore-diff:yes"; fi
    if [ "$(settings get secure always_on_vpn_app 2>/dev/null)" = "$(cat "$R/config/app.package" 2>/dev/null)" ]; then
        runtime_status="$runtime_status|always-on:yes"
    fi
    session_report=$(runtime_session_report | tr '\n' '|')
    runtime_status="$runtime_status|${session_report}bootMs:$(boot_ms)"
    status_digest=$(printf '%s:%s:%s' "$auth_token" "$auth_nonce" "$runtime_status" | sha256sum | cut -d' ' -f1)
    reply=$(printf 'probe %s %s %s\n' "$auth_nonce" "$status_digest" "$runtime_status" |
        timeout -s KILL 1 nc -w 1 127.0.0.1 "$auth_port" 2>/dev/null) || { echo unknown; return; }
    case "$reply" in granted\ *|revoked\ *|unknown\ *) ;; *) echo unknown; return ;; esac
    verdict=${reply%% *}
    expected=$(printf '%s:%s:%s' "$auth_token" "$auth_nonce" "$verdict" | sha256sum | cut -d' ' -f1)
    if [ "$reply" = "$verdict $expected" ]; then echo "$verdict"; else echo unknown; fi
}

notify_app_cleanup() {
    [ -r "$R/config/app-auth" ] || return 0
    read -r auth_port auth_token < "$R/config/app-auth"
    auth_nonce=$(cat /proc/sys/kernel/random/uuid)
    digest=$(printf '%s:%s:%s' "$auth_token" "$auth_nonce" "$1" | sha256sum | cut -d' ' -f1)
    printf 'cleaned %s %s %s\n' "$1" "$auth_nonce" "$digest" |
        timeout -s KILL 1 nc -w 1 127.0.0.1 "$auth_port" >/dev/null 2>&1 || true
}

runtime_session_report() {
    printf 'session:%s\nstop:%s\n' "$(cat "$STATE/session" 2>/dev/null)" "$(cat "$STATE/session-stop" 2>/dev/null)"
}

authorization_evidence() {
    date +%s
    cat /proc/uptime /proc/sys/kernel/random/boot_id
    auth_uid=${1:-$(cat "$R/config/app.uid" 2>/dev/null)}
    case "$auth_uid" in ''|*[!0-9]*) return 1 ;; esac
    case "${2:-$(cat "$R/config/root.manager" 2>/dev/null)}" in
        kernelsu)
            stat -c '%s %Y' /data/adb/ksu/.allowlist
            od -An -v -tu1 /data/adb/ksu/.allowlist | awk -v uid="$auth_uid" '
                function u32(i) {return b[i]+256*b[i+1]+65536*b[i+2]+16777216*b[i+3]}
                {for(i=1;i<=NF;i++) b[n++]=$i}
                END {
                    printf "header:"; for(i=0;i<8 && i<n;i++) printf " %s", b[i]; print "";
                    v=u32(4); stride=v==4 ? 784 : 776;
                    if (v<2 || v>4 || (n-8)%stride) {print "unknown ABI"; exit 1}
                    for(p=8;p<n;p+=stride) {
                        key=""; for(k=4;k<260 && b[p+k];k++) key=key sprintf("%c",b[p+k]);
                        if(key=="com.follow.clash.root" && u32(p+260)==uid) {
                            printf "app-record offset=%s:",p;
                            for(i=p;i<p+stride;i++) printf " %s",b[i]; print "";
                        }
                    }
                }'
            ;;
        magisk) magisk --sqlite "SELECT policy,until FROM policies WHERE uid=$auth_uid;" ;;
        apatch) sed -n '1p;/^com[.]follow[.]clash[.]root,/p' /data/adb/ap/package_config ;;
        *) return 1 ;;
    esac
}
