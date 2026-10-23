#!/bin/sh
set -u
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$FAKE_NET/calls"
case "$name" in
    pm)
        [ "$*" = 'path com.follow.clash.root' ] || [ "$*" = 'list packages com.follow.clash.root' ] || exit 64
        case "$(cat "$FAKE_NET/package" 2>/dev/null)" in
            absent) : ;;
            android-absent) if [ "$1" = path ]; then exit 1; fi ;;
            binder-failure) echo 'Error: package service unavailable' >&2; exit 1 ;;
            fail) exit 1 ;;
            timeout) sleep 3; exit 1 ;;
            prefix) [ "$1" != list ] || echo package:com.follow.clash.root.extra ;;
            *)
                if [ "$1" = path ]; then echo package:/data/app/com.follow.clash.root-random/base.apk;
                else echo package:com.follow.clash.root; fi
                ;;
        esac
        ;;
    log) printf '%s\n' "$*" >> "$FAKE_NET/logcat" ;;
    settings) echo off ;;
    nc) [ ! -f "$FAKE_NET/unhealthy" ] && printf 'HTTP/1.0 200 OK\r\n\r\n' ;;
    iptables-save|ip6tables-save)
        echo '*filter'
        echo ':OUTPUT ACCEPT [0:0]'
        [ ! -f "$FAKE_NET/${name%-save}.chain" ] || echo '-N FCR_OUTPUT'
        echo COMMIT
        ;;
    iptables|ip6tables)
        shift 2
        case "$1" in
            -N) touch "$FAKE_NET/$name.chain" ;;
            -I) touch "$FAKE_NET/$name.jump" ;;
            -C)
                if [ "$2" = OUTPUT ]; then [ -f "$FAKE_NET/$name.jump" ];
                elif [ "$2" = FCR_OUTPUT ] && [ "$3" = '!' ]; then [ -f "$FAKE_NET/$name.guard" ];
                else exit 1; fi
                ;;
            -A) if [ "${3:-}" = '!' ] && [ "${5:-}" = flcrtun0 ] && [ "${6:-}" = -j ]; then touch "$FAKE_NET/$name.guard"; fi ;;
            -D) rm -f "$FAKE_NET/$name.jump" ;;
            -X) [ ! -f "$FAKE_NET/block-cleanup" ] || exit 1; rm -f "$FAKE_NET/$name.chain" "$FAKE_NET/$name.guard" ;;
            -S)
                if [ "${2:-}" = FCR_OUTPUT ]; then [ -f "$FAKE_NET/$name.chain" ];
                elif [ -f "$FAKE_NET/$name.chain" ]; then echo '-N FCR_OUTPUT'; fi
                ;;
        esac
        ;;
    ip)
        case "$1" in -4|-6) family=$1; shift ;; *) family=-4 ;; esac
        case "$1:$2" in
            rule:show) cat "$FAKE_NET/$family.rules" 2>/dev/null || true ;;
            rule:add) printf '%s: %s\n' "$4" "$*" >> "$FAKE_NET/$family.rules" ;;
            rule:del)
                awk -F: -v p="$4" '$1 != p' "$FAKE_NET/$family.rules" > "$FAKE_NET/$family.rules.tmp"
                mv "$FAKE_NET/$family.rules.tmp" "$FAKE_NET/$family.rules"
                ;;
            route:show) [ ! -f "$FAKE_NET/tun" ] || echo 'default dev flcrtun0 table 2022' ;;
            route:flush) : ;;
            link:show)
                if [ -f "$FAKE_NET/tun" ]; then echo '1: flcrtun0: <UP>';
                elif [ -n "${3:-}" ]; then exit 1; fi
                ;;
            link:delete) rm -f "$FAKE_NET/tun" ;;
        esac
        ;;
esac
