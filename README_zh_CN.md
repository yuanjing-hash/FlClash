# FlClash TUN

**基于 [FlClash](https://github.com/chen08209/FlClash) 的 Android Root TUN 版本，使用 mihomo 内核。**

[English](README.md) · [简体中文](README_zh_CN.md)

[![Release](https://img.shields.io/github/v/release/yuanjing-hash/FlClash?label=FlClash%20TUN)](https://github.com/yuanjing-hash/FlClash/releases/latest)
[![License](https://img.shields.io/github/license/yuanjing-hash/FlClash)](LICENSE)

本仓库**仅发布 Android APK**。在 Android VPN 模式之外增加原生 Root TUN，并继续通过同一套 FlClash 界面控制配置、节点、分流规则、DNS、应用筛选、日志和流量统计。

## 下载

从[本仓库 Releases](https://github.com/yuanjing-hash/FlClash/releases/latest) 下载签名 APK。大部分手机选择 **arm64-v8a**；x86_64 供兼容的 64 位 Android 设备或模拟器使用。

- 包名：`com.follow.clash.root`，与上游 FlClash 分开安装。
- 首个 TUN 正式版为 **1.0.0**。
- 正式发布使用长期保存的签名身份，覆盖升级兼容性见每次发布说明。
- 下载后可使用发布附件中的 `SHA256SUMS` 校验文件。

## VPN 与 Root TUN

- **VPN**：通过 Android VpnService 接管流量，无需 root。
- **Root TUN**：由原生内核和 root 路由接管流量，需要支持的 root 管理器及具备 TUN 支持的内核。
- 在主页的流量接管卡片选择 **VPN / Root TUN**。可通过仪表盘编辑按钮添加卡片或调整位置。
- 切换模式时先停止当前连接，选好后点击主页的开始按钮启动。
- 状态卡会显示启动、授权、恢复和失败状态；服务就绪后才开始检测 IP 和质量。
- root 授权、开机自启、清理及诊断日志导出仍位于**网络设置**。

Root TUN 已在 KernelSU 设备上进行测试。x86_64 包进行构建检查，具体设备行为取决于其内核和 root 环境。

## 从源码构建

[构建流程](.github/workflows/build.yaml)固定使用 Flutter 3.47.6、Go 1.27.1、JDK 17 和 Android NDK r28c。还需要 Git 与 POSIX shell；Windows 可使用 Git for Windows。

```sh
git clone --recurse-submodules https://github.com/yuanjing-hash/FlClash.git
cd FlClash
flutter pub get
flutter build apk --release --target-platform android-arm64 --dart-define=APP_ENV=stable
```

Android 构建会自动运行 `tool/prepare_core.sh`，将版本化的 `core/patches/root-cache-path.patch` 应用到固定版本的 mihomo 子模块，使 Root 内核与内嵌内核分别使用自己的持久化缓存。这是本项目双内核集成所需的缓存路径能力扩展，默认缓存路径和代理算法保持原样。

直接检查 Go 代码前先准备内核源码：

```sh
sh tool/prepare_core.sh
cd core
CGO_ENABLED=0 go test .
```

正式签名使用 `android/app/keystore.jks`，以及被 Git 忽略的 `android/local.properties` 中的 `keyAlias`、`storePassword`、`keyPassword`。GitHub Actions 通过加密的 `KEYSTORE`、`KEY_ALIAS`、`STORE_PASSWORD`、`KEY_PASSWORD` secrets 提供这些配置；正式标签缺少签名时会停止发布。不要将签名文件或密码提交到 Git。

## 上游与许可证

- 上游项目：[chen08209/FlClash](https://github.com/chen08209/FlClash)。
- 代理内核：`core/Clash.Meta` 中固定版本的 FlClash mihomo 分支。
- 原生 Root TUN 实现对照了 [AsteriskMETA](https://github.com/Asterisk4Magisk/AsteriskMETA) 和 [asteriskd](https://github.com/Asterisk4Magisk/asteriskd)。
- 遵循 GPL-3.0，见 [LICENSE](LICENSE)，保留上游版权声明和许可证。

本 TUN 版本的问题请在[本仓库](https://github.com/yuanjing-hash/FlClash/issues)提交，并附上版本、root 管理器和移除私人配置后的 Root TUN 诊断日志。
