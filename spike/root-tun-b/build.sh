#!/bin/sh
set -eu

base=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
source_dir=$base/.cache/source
revision=8380d0e7462f061a964323e9bf3129a236fcc5d5
mkdir -p "$base/.cache/tmp" "$base/logs" "$base/bin/arm64" "$base/bin/x86_64" "$base/bin/linux-x86_64"
export GOCACHE="$base/.cache/go-build"
export GOMODCACHE="$base/.cache/go-mod"
export GOPATH="$base/.cache/go"
export GOTOOLCHAIN=local
export TMPDIR="$base/.cache/tmp"

if [ ! -d "$source_dir/.git" ]; then
    git clone --depth 1 --branch FlClash https://github.com/chen08209/Clash.Meta "$source_dir"
fi
if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]; then
    git -C "$source_dir" fetch --depth 1 origin "$revision"
    git -C "$source_dir" checkout --detach "$revision"
fi
[ -z "$(git -C "$source_dir" status --porcelain)" ] || exit 1

ndk=${ANDROID_NDK_HOME:-$base/.cache/android-ndk-r27c}
cc=$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android29-clang
if [ ! -x "$cc" ]; then
    printf '%s\n' 'x86_64 需要 NDK r27c；设置 ANDROID_NDK_HOME，或按 README 下载到 .cache。' >&2
    exit 1
fi

cd "$source_dir"
flags='-s -w -X github.com/metacubex/mihomo/constant.Version=FlClash-spike-8380d0e'
CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -tags with_gvisor -trimpath -ldflags "$flags" -o "$base/bin/arm64/mihomo" .
CGO_ENABLED=1 GOOS=android GOARCH=amd64 GOAMD64=v1 CC="$cc" go build -tags with_gvisor -trimpath -ldflags "$flags" -o "$base/bin/x86_64/mihomo" .
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOAMD64=v1 go build -tags with_gvisor -trimpath -ldflags "$flags" -o "$base/bin/linux-x86_64/mihomo" .

for arch in arm64 amd64; do
    destination=arm64
    [ "$arch" != amd64 ] || destination=x86_64
    CGO_ENABLED=0 GOOS=linux GOARCH=$arch GOAMD64=v1 go build -trimpath -ldflags '-s -w' -o "$base/bin/$destination/probe" "$base/probe.go"
done
{
    git rev-parse HEAD
    go version
    printf 'NDK: %s\n' "$ndk"
    "$cc" --version
    cat "$ndk/source.properties" 2>/dev/null || true
    wc -c "$base"/bin/*/mihomo "$base"/bin/*/probe
    sha256sum "$base"/bin/*/mihomo "$base"/bin/*/probe
} > "$base/logs/build-manifest.txt"
cat "$base/logs/build-manifest.txt"
