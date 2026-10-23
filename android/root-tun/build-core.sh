#!/bin/sh
set -eu

[ "$#" -eq 4 ] || { echo 'usage: build-core.sh SOURCE OUTPUT ABI NDK' >&2; exit 64; }
source_dir=$1
output=$2
abi=$3
ndk=$4
[ -f "$source_dir/go.mod" ] || {
    echo 'Root TUN requires the pinned core/Clash.Meta submodule (git submodule update --init --recursive).' >&2
    exit 1
}
mkdir -p "$output"
output=$(CDPATH='' cd "$output" && pwd)
cd "$source_dir"
export GOOS=android
export CGO_ENABLED=0
export GOTOOLCHAIN=local
case "$abi" in
    arm64-v8a) export GOARCH=arm64 ;;
    x86_64)
        export GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=1
        case "$(uname -s)" in
            Linux) host=linux-x86_64 ;;
            Darwin) host=darwin-x86_64 ;;
            *) echo 'Root TUN x86_64 build requires Linux or macOS NDK tools.' >&2; exit 1 ;;
        esac
        CC=$ndk/toolchains/llvm/prebuilt/$host/bin/x86_64-linux-android29-clang
        export CC
        [ -x "$CC" ] || { echo 'Missing NDK x86_64 API 29 compiler.' >&2; exit 1; }
        ;;
    *) echo 'Root TUN supports arm64-v8a and x86_64 only.' >&2; exit 64 ;;
esac
go build -tags with_gvisor -trimpath -ldflags '-s -w -X github.com/metacubex/mihomo/constant.Version=FlClash-root-native' \
    -o "$output/libroot_mihomo.so.tmp" .
mv "$output/libroot_mihomo.so.tmp" "$output/libroot_mihomo.so"
