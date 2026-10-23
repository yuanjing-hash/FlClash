# ADR-0001：Android Root TUN 核心运行位置

日期：2026-10-23；状态：**Accepted（采用方案 B，待真机验证）**。

## 背景

冻结的 PRD v1（共享电脑 `/workspace/flclash-pm/PRD-v1.md`）要求 Android ≥10 的 Magisk/KernelSU/APatch 上不经 VpnService、无钥匙图标；与 VPN 模式互斥；**US-13 AC1 要求开机后不打开 App 即接管网络**。DNS/IPv6 防漏、崩溃恢复失败30秒内直连、卸载60秒内恢复，以及关闭后与网络快照一致均为硬约束。

现有 Android 是 Builder 建 TUN → `Core.startTun` → gomobile；`core/tun/tun.go` 关闭自动路由并依赖 VPN protect/UID 回调。桌面 `core/cmd/core` / `core/server.go` 虽有独立进程与 JSON IPC，但被 `!android` 排除，且宿主断连会释放核心，不能直接作为开机实现。

## 决策

采用 **B：root 独立 mihomo 核心**。借鉴桌面入口新增 Android root 入口，编译 arm64/x86_64；核心自建 TUN、auto-route，agent 管理网络事务与生命周期，独立 root watchdog 兜底。App 经 Kotlin + Unix socket 控制/展示，保持 `${packageName}/core` 的 CoreMethodCall/CoreMethodResponse 不变，Flutter 不直连核心。防回环在 root 侧用核心 fwmark/出口规则，应用识别在 root 侧完成。

首版只用一个 `/data/adb/service.d/flclash-root.sh` 薄入口，运行时文件均在 `/data/adb/flclash-root/`；关闭 Root 功能/卸载清空。改动优先新文件，现有生命周期与传输只留接缝，避免修改 mihomo。所有控制 socket 先用 SO_PEERCRED 校验 UID，异 App 拒绝并记日志。

## 备选

| 方案 | 取舍 |
|---|---|
| A：su helper 建 TUN，Unix socket + SCM_RIGHTS 把 fd 交给 App gomobile，复用 Core.startTun | 不建 VPN 也可无钥匙图标；SELinux 是否允许 untrusted_app 用 su 域 fd 待核实；protect/getConnectionOwnerUid 不再可依赖。开机无 App 时无人接 fd，**原案不满足 US-13 AC1**；另加原生宿主会改变方案范围。 |
| 标准 root 模块 `/data/adb/modules/...` 打包 | 可利用模块安装/卸载生命周期，但增加三家管理器适配与分发成本；首版不采用，不替代独立看门狗。后续有 spike/维护收益证据再建 ADR。 |

## 后果

B 支持无 App 冷启动及独立清理；代价是新增双 ABI root 产物、配置自足副本、可重连 IPC、崩溃监护及安全面。auto-route 字段存在不代表 Android 路由正确；SELinux、netd fwmark、DNS/IPv6防漏、身份识别与快照还原仍须矩阵验证。所有状态/超时/错误码/认证/脚本边界遵循 [TDD](../root-tun/TDD.md)，不新增 PRD 状态。

仅 Gradle applicationId 改为 `com.follow.clash.root`；Dart packageName / Kotlin Components.PACKAGE_NAME 和平台通道名保持 `com.follow.clash`。首版不做分应用代理、完整IPv6代理或分身空间；IPv6不得直连泄露。

## 验证条件

首个真机环境是小米 17 Pro Max（Android 17，KernelSU），由老板安装 CI 产出的 arm64 debug APK 手动测试，不跑脚本或 adb；诊断信息全部通过 App 内「导出诊断日志」取得（ip rule、路由、tun 网卡、核心日志）。**真机上能开启 Root TUN、建出 tun 网卡并跑通代理流量，且关闭后规则与开启前一致，即视为 B 验证通过**；不以“编译成功”代替流量成功。若真机证明 B 不可行，本 ADR 改为 Superseded 并经项目经理评审下一步，不擅自放宽 US-13 AC1。其余待核实项（TDD W1–W6）仍是发布门槛；Magisk、APatch 及其他 Android 版本待后续设备补测。
