# FlClash TUN

**Android Root TUN edition of [FlClash](https://github.com/chen08209/FlClash), powered by mihomo.**

[English](README.md) · [简体中文](README_zh_CN.md)

[![Release](https://img.shields.io/github/v/release/yuanjing-hash/FlClash?label=FlClash%20TUN)](https://github.com/yuanjing-hash/FlClash/releases/latest)
[![License](https://img.shields.io/github/license/yuanjing-hash/FlClash)](LICENSE)

This fork publishes **Android APKs only**. It adds a native Root TUN mode alongside the Android VPN mode, while keeping profile selection, proxy groups, routing rules, DNS, app filtering, logs and traffic statistics under the same FlClash UI.

## Download

Download the signed APK from [this repository's Releases](https://github.com/yuanjing-hash/FlClash/releases/latest). Most phones need **arm64-v8a**; x86_64 is intended for compatible 64-bit Android devices and emulators.

- Package: `com.follow.clash.root`, separate from upstream FlClash.
- The first stable TUN release is **1.0.0**.
- Stable releases use a persistent signing identity; upgrade compatibility is recorded in each release's notes.
- Check the download against the release's `SHA256SUMS` file.

## VPN and Root TUN

- **VPN** uses Android VpnService and does not require root.
- **Root TUN** uses the native core and root-managed routing. It requires a supported root manager and a kernel with TUN support.
- Choose **VPN / Root TUN** in the dashboard's traffic takeover card. Add or reorder that card through the dashboard edit button.
- Changing mode stops the current connection. Press the main start button to start the selected mode.
- The status card shows startup, authorization, recovery and failure states. IP and quality checks wait until the service is ready.
- Root authorization, boot startup, cleanup and diagnostic export remain in **Network settings**.

Root TUN has been tested on a KernelSU device. The x86_64 package receives build checks; device behavior depends on the device's kernel and root environment.

## Build from source

The Android toolchain is pinned in [the workflow](.github/workflows/build.yaml): Flutter 3.47.6, Go 1.27.1, JDK 17 and Android NDK r28c. Git and a POSIX shell are also required; on Windows use Git for Windows.

```sh
git clone --recurse-submodules https://github.com/yuanjing-hash/FlClash.git
cd FlClash
flutter pub get
flutter build apk --release --target-platform android-arm64 --dart-define=APP_ENV=stable
```

Android builds automatically run `tool/prepare_core.sh`. It applies the versioned `core/patches/root-cache-path.patch` to the pinned mihomo submodule so the Root and embedded cores use independent persistent caches. The patch adds a cache-path capability for this fork's two-core integration; it leaves the default cache path and proxy algorithms intact.

For direct Go checks, prepare the source first:

```sh
sh tool/prepare_core.sh
cd core
CGO_ENABLED=0 go test .
```

Release signing uses `android/app/keystore.jks` plus `keyAlias`, `storePassword` and `keyPassword` in the ignored `android/local.properties`. GitHub Actions stores these as the encrypted `KEYSTORE`, `KEY_ALIAS`, `STORE_PASSWORD` and `KEY_PASSWORD` secrets. A stable tag refuses to publish when signing is unavailable. Keep signing files and passwords out of Git.

## Upstream and license

- Upstream application: [chen08209/FlClash](https://github.com/chen08209/FlClash).
- Core: the pinned FlClash mihomo fork under `core/Clash.Meta`.
- Native Root TUN implementation was compared with [AsteriskMETA](https://github.com/Asterisk4Magisk/AsteriskMETA) and [asteriskd](https://github.com/Asterisk4Magisk/asteriskd).
- GPL-3.0; see [LICENSE](LICENSE). Upstream copyright notices and licenses are preserved.

Report issues for this TUN edition in [this repository](https://github.com/yuanjing-hash/FlClash/issues). Include the app version, root manager and exported Root TUN diagnostics after removing private configuration data.
