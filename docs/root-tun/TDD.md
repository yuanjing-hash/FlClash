# Android Root TUN 技术方案（草案）

2026-10-23；基线：`yuanjing-hash/FlClash` / 上游 v0.9.1；架构 **Proposed，倾向 B**，见 [ADR-0001](../adr/0001-root-tun-architecture.md)。本文定义待实现的契约，不表示能力已交付。

依据：[冻结 PRD v1](/workspace/flclash-pm/PRD-v1.md) §5.1、附录 B、[团队规范](/workspace/flclash-docs/CONTRIBUTING.md)、[仓库架构](../../.agents/architecture.md)、[规则](../../.agents/rules.md)。需求变更交项目经理；首版不做分应用代理、完整 IPv6 代理、分身空间。Android ≥10，仅 Magisk / KernelSU / APatch。

## 1. 背景与现状链路

以下均核对当前 worktree 源码；路径相对仓库根，表内 Android 路径为完整路径。

| 层 | 文件与实际职责 |
|---|---|
| Flutter 配置 | `lib/providers/state/system.dart::vpnOptions` 从 VPN 设置、TUN 配置生成 `lib/models/core.dart::VpnOptions`（enable、stack、ipv6、dnsHijacking、路由、访问控制等）；它不是 root 配置。 |
| Flutter 桥 | `lib/core/lib.dart::CoreLib` 初始化/同步/调用 `lib/plugins/service.dart::Service`；`com.follow.clash/service` 承载生命周期与事件，`com.follow.clash/core` 的 `invokeMethod` 接收 JSON 字符串、返回 JSON UTF-8 `Uint8List`。 |
| 原生入口 | `android/app/src/main/kotlin/com/follow/clash/plugins/ServicePlugin.kt` 乐观确认 start/stop，Core 调用走串行后台队列；同目录 `AppPlugin.kt::prepareVpn` 调 `VpnService.prepare`，需要时弹系统授权。 |
| 原生意图 | `android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt`（`ServiceState` 委托）仲裁最新意图、串行准备/迁移；同目录 `ServiceController.kt::start` 按 `VpnOptions.enable` 绑定 `VpnService` 或 `ProxyService`，独占 binding/runtime。 |
| 建 TUN | `android/service/src/main/java/com/follow/clash/service/VpnService.kt::handleStart` 用 Builder 加地址/路由/DNS、`establish().detachFd()`；IPv4 `198.18.0.1/30`、DNS `.2`；交给 `android/core/src/main/java/com/follow/clash/core/Core.kt::startTun`，同时传 protect、resolveUid、resolvePackage。 |
| Go 绑定 | `core/mobile/mobile.go::StartTun` → `core/lib.go::StartTun` → `core/tun/tun.go::Start`。后者 dup fd 后创建 `LC.Tun`，`AutoRoute=false`、`AutoDetectInterface=false`，由 VPN 而非核心管系统路由。 |
| 防回环/识别 | `core/lib.go::installHooks` 一次安装 socket/package hooks；`handleProtect` 调 VPN protect；`handleResolveProcess` 在 Android ≥29 调原生 `ConnectivityManager.getConnectionOwnerUid`，再查包名。脱离活动 VPN 不能继续依赖这两个权限路径。 |
| 独立核心 | `core/cmd/core/main.go` 调 `core/server.go::StartServer`；核心主动连接宿主，4 字节小端长度 + JSON，宿主断连即返回并释放核心；`core/dial_socket.go` 实现 Unix socket。三者均被 `!android` 排除。`core/lifecycle.go::updateListeners` 还明确跳过 Android TUN。 |

只将 Gradle `applicationId` 改为 `com.follow.clash.root`；`lib/common/constant.dart::packageName` 与 `android/common/src/main/java/com/follow/clash/common/Components.kt::PACKAGE_NAME` **仍为 `com.follow.clash`**，Kotlin namespace 和通道名不随 applicationId 改。按实际安装包取得 UID，不用通道常量判断卸载。

## 2. A / B 对比与推荐

| 维度 | A：root helper 建 TUN，SCM_RIGHTS 交 fd 给 App gomobile | B：root 独立 mihomo 核心（倾向） |
|---|---|---|
| 无钥匙图标 | 不创建 VPN 即满足；不能调用 prepare/Builder | 不创建 VPN，满足；系统其他 VPN 的图标不在本 App 控制内 |
| 关闭后与快照一致 | helper 记录并撤销全部资源；App 死亡仍须独立清理 | agent 事务日志 + 独立看门狗清理；两案都必须逐项比对快照 |
| SELinux | su 域 fd 传给 untrusted_app 后能否使用待实测 | su 域建 TUN 较直接；执行、netlink、App 连接 socket 仍需实测 |
| 防回环 | VPN protect 失效，需 root 配标记/规则补齐 | 核心出站 SO_MARK + 路由跳过；不得豁免整个 UID 0 |
| 应用识别 | getConnectionOwnerUid 失效，须增加 root 查询 | root INET_DIAG / procfs → UID → 包名；首版仅展示，不做分应用开关 |
| 崩溃清理 | App 核心死后 helper/watchdog 接管 | agent 恢复核心，watchdog 在 agent/App 同死时接管 |
| 开机自启 | App 不在就无 fd 接收方；原案违反 **US-13 AC1** | service.d 直接启动，不依赖 App/Flutter |
| 上游合并成本 | 复用 startTun，但新增 JNI/fd 交接及回调替代 | 新增 root 入口/传输/后端适配；少量 build tag、TUN 创建接缝，保留协议 |
| 安全 | fd/socket 身份、关闭归属需证明 | 常驻 root 面较大；固定命令、SO_PEERCRED、最小文件权限 |
| 工作量 | 表面较小；满足冷启动必须增加原生宿主，收益消失 | 中等偏大；可复用 Go 方法分发、配置及统计 |

推荐 B。基于 `core/cmd/core` 的结构新增 Android root 入口，交叉编译 `android/arm64`、`android/amd64`，APK **仅出 arm64-v8a 和 x86_64**（不出 armeabi-v7a）。**不是原样编译桌面入口**：增加可重连 IPC、无宿主也运行、root 模式 TUN 创建路径；不触发 gomobile 的 VPN hooks。优先新文件：`core/cmd/root-core/`、`core/root_*`、原生 `root/`、`RootTunPlugin`、Dart root 通道/模型、`scripts/root-tun/`；现有 ServiceState、ServicePlugin、Go lifecycle 只留模式/传输接缝，尽量不改 `Clash.Meta`。

## 3. 路由与 DNS 接管

### 3.1 已核实的字段与限制

子模块初始化因共享 Git 配置只读失败，改从 GitHub 读取**同一 gitlink SHA `8380d0e7462f061a964323e9bf3129a236fcc5d5`**，非用最新文档推测。出处：

- M1：[LC.Tun](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/listener/config/tun.go)、[RawTun / parseTun](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/config/config.go#L273)。
- M2：[sing_tun/server.go](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/listener/sing_tun/server.go)、[server_android.go](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/listener/sing_tun/server_android.go)、[dns.go](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/listener/sing_tun/dns.go)。
- S1：本仓库 `core/go.mod` 固定 [sing-tun v0.4.27 tun_linux.go](https://github.com/MetaCubeX/sing-tun/blob/v0.4.27/tun_linux.go)、[tun_rules.go](https://github.com/MetaCubeX/sing-tun/blob/v0.4.27/tun_rules.go)、[tun.go](https://github.com/MetaCubeX/sing-tun/blob/v0.4.27/tun.go)。
- S2：[redirect_linux.go](https://github.com/MetaCubeX/sing-tun/blob/v0.4.27/redirect_linux.go)、[redirect_iptables.go](https://github.com/MetaCubeX/sing-tun/blob/v0.4.27/redirect_iptables.go)、[monitor_android.go](https://github.com/MetaCubeX/sing-tun/blob/v0.4.27/monitor_android.go)。

| YAML 字段（M1 中均存在） | Android 源码行为 / 首版选择 |
|---|---|
| `auto-route` | M2 传给 sing-tun；S1 用 netlink 配路由/rule、监听 Android 默认网络。首版 true；untrusted_app 限制不能外推到 su，root 域可用性待实测。 |
| `auto-redirect` | M2 要求 auto-route；S2 Android 走 `/system/bin/iptables`、仅启 IPv4，非 nft，TCP redirect 与 UDP DNS 规则不等于全协议接管。首版 **false**，避免重复规则所有者。 |
| `strict-route` | S1 对未配置地址族加入 unreachable；不等于完成 IPv6/DNS 防泄露。首版 true，并另有 IPv6 防漏规则。 |
| `include-package` / `exclude-package` | 字段下传，但 M2 Android 的 `buildAndroidRules` 是空实现；sing-tun 的包名→UID 转换须另调 BuildAndroidRules，不能宣称此链路已生效。首版不写入。 |
| `include-uid` | M2 转 UID range，S1 用 UIDRange / 排除范围构造 policy rules；内核支持需矩阵实测。首版不提供用户分流设置。 |
| `iproute2-table-index` / `iproute2-rule-index` | M2 传给 S1；默认 2022 / 9000，自动清理会遍历 rule-index 至 +10。必须整段查空，不能只看首条。 |
| `dns-hijack` | M2 解析 `any:53` 为通配地址；dns.go 对已进入 TUN 的 TCP/UDP 53 转给核心 DNS。它本身不把未入 TUN 的流量拉进来，也不处理 853/DoH。 |

### 3.2 首版策略（数值为候选，spike 固化）

单次启动先查冲突，再独占表 **2022**、优先级 **8990–9011**、mark **`0x40000000/0x40000000`**、网卡 `flcrtun0`、链前缀 `FCR_`。冲突时不覆盖，报 `NETWORK_RULES_APPLY_FAILED`。保留系统 local 规则（通常 pref 0）；Android 多路由表环境不得把核心豁免简单写成 `lookup main`。

| 顺序 | 规则意图 |
|---|---|
| pref 8990，双族 | 核心 SO_MARK 命中 → `goto 9011`，越过本项目接管区，继续系统/netd 选路；同时绑定已探测的物理出口。核心所有协议、DNS、UDP listen/ICMP 出站均覆盖标记；不按 UID 0 整体绕过。 |
| pref 8991，IPv4 | 本机 `iif lo`、非核心流量 → 表 2022，补足 Android 已绑定源地址/系统 DNS 的覆盖；不扩展为热点网关。 |
| pref 9000–9010 | LC.Tun `auto-route=true`、表 2022、rule-index 9000、`strict-route=true`；表默认 IPv4 路由指向 TUN。8991 与自动规则去重/回环需 spike 抓包确认。 |
| IPv6 | 不配置 TUN IPv6 地址，阻断非 loopback 的 IPv6 对外业务流量（FCR filter + policy unreachable）；仅保留必要链路控制如 NDP，不能开放 IPv6 DNS/853。核心首版也用 IPv4 出口，配置仅有 IPv6 节点时启动失败，禁止默默直连。 |

`dns-hijack: [any:53]` 接管所有应用（含 netd）UDP/TCP 53；FCR OUTPUT 防漏链不允许非核心明文 53 从物理网卡出去。核心上游 DNS 仅按已验证配置通过标记出口；拒绝解析器循环/无可用上游，报 `DNS_TAKEOVER_FAILED`。自检同时证明 TCP/UDP 查询被接管、物理出口无旁路，才发布 running。

私人 DNS **自动**：FCR OUTPUT 对非核心的外部 TCP/UDP 853 作 REJECT，促使系统退回 53；日志记 `PRIVATE_DNS_AUTO_TAKEN_OVER`，不弹窗。**严格**：不加 853 拦截、不改用户服务器，仅 `PRIVATE_DNS_STRICT` 横幅/说明，按冻结 US-05 AC5 豁免 AC1/AC2；IPv6 防漏仍生效。私人 DNS 状态变化由原生/无 App 时 root 监测，原子更新规则。加密 DoH 本身不被当作 53 劫持，仍随业务流量进入 TUN。

启动事务：①配置可读/核心可启动、快照落盘并启动看门狗；②先安装 DNS/IPv6 防漏及核心绕过；③建 TUN、auto-route、补充本机接管；④连通性/DNS/回环自检；⑤提交 running。失败按逆序回滚，未清理成功不能报告直连。候选路由、mark 与 Android fwmark 位是否冲突均为待核实 W1。

快照覆盖 `ip -4/-6 rule`、所有路由表、iptables/ip6tables 的 nat/mangle/filter、网卡/地址；若后续用 nft，另含完整 nft ruleset。启动前记录原值与拟创建资源，执行前写 undo journal，成功后记 applied。停止先拆引流，再停核心/删 TUN，恢复被改原值并删除自有增量；禁止全局 flush、无条件 restore 覆盖其他模块。自动规则清理范围也归 manifest 管理。验收对比开启前后上述快照（仅去时间/计数器、排序），**必须一致**；外部并发修改无法等同“本项目残留”，出现差异报告 `CLEANUP_FAILED`，保留证据，跨切网快照口径见 Q1。

## 4. 进程与生命周期

`ServiceState` 仍是 Android 用户意图/模式仲裁唯一入口；新增 Root backend 提交意图到 root agent。agent 独占 root 生命周期/网络事务，持久化 TunState；Kotlin 仅缓存/转发，不再自行推断 running。watchdog 只在 agent 失联后持锁接管，不能与 agent 双写。Flutter 只镜像状态。默认 Root TUN 关闭，安全模式不得启动 root 或写规则。

| 当前状态 | 事件 → 下一状态（固定枚举，仅此八种） |
|---|---|
| `disabled` | 启动：有授权 → starting，无授权 → awaitingAuth；前提不足 → degraded。 |
| `awaitingAuth` | Magisk 允许 / KSU、APatch 重新检测成功 → starting；Magisk 拒绝/30s → failed；KSU、APatch 未授权 → 原状态、`ROOT_GRANT_NOT_DETECTED`；取消 → disabled。 |
| `starting` | ≤10s 自检通过 → running；失败且回滚完成 → failed（含 START_TIMEOUT）；关闭 → stopping。 |
| `running` | 核心死/规则损坏 → recovering；关闭/切 VPN/撤权 → stopping。 |
| `recovering` | 恢复 → running（CORE_RECOVERED）；30s 失败或滚动 5min 第 3 次核心崩溃 → stopping → failed。用户停止也经 stopping，禁止旧恢复复活。 |
| `stopping` | ≤3s 清理完成：主动停止 → disabled，错误停止 → failed；清理不全发 CLEANUP_FAILED，兜底重试，见 Q2。 |
| `failed` | 重试 → awaitingAuth/starting；确认/关闭 → disabled；检测前提不足 → degraded。 |
| `degraded` | 回前台/重新检测满足前提 → disabled，不自动启动。 |

Magisk：仅显式 requestAuth/start 可触发 su 弹窗，30s 后杀**本次请求的记录 PID**并失效化 revision；迟到允许不能启动。KernelSU/APatch：进入 awaitingAuth，指引打开管理器为 `com.follow.clash.root` 授权，显示“我已授权，重新检测”，无期限等待，可取消；不把 su 非零结果一律当成拒绝。检测不得弹授权窗，探测方式见 W3。

核心崩溃由独立 root agent 立即恢复；watchdog 每 **1s** 检查 agent/core 心跳与 PID+启动时间，不能仅 kill -0。恢复预算从最早失去健康时计：检测 ≤1s、恢复到第 27s、留 ≤3s 清理，合计 ≤30s；第 3 次/5min 立即停止重试。先保留接管规则；不能恢复就拆规则 fail-open。watchdog 与 agent 非父死联动、关闭 su 管道不退出，App/core/agent 被 kill -9 后仍能清理；不承诺所有 root 守护进程同时被人为杀死后的自救。

撤权每 ≤5s 通过管理器有效授权探测，不能拿“已有 root daemon 还活着”当授权证明。撤权走 stopping → failed（ROOT_PERMISSION_REVOKED），禁自启并删入口；root 侧已有权限负责完成清理。App 强停不杀 root 核心；下次结合 ApplicationExitInfo/会话记录核对网络，发 LAST_SESSION_ABNORMAL_EXIT，不能据此把仍运行的核心标成 disabled。

网络切换由 root netlink/默认接口监测处理：保留防漏，刷新物理出口、路由、DNS 连接；必要时 recovering，10s 内恢复（NFR-05），不得等 Flutter 上线。磁贴、快捷方式、原生通知停止、Always-on/revoke 都进 ServiceState，同一 intentRevision 最新者胜出；App 不在时 receiver 转交 agent。`MODE_SWITCHING` 仅错误码/提示，不能新增状态：VPN→Root 先确认 VPN 停止再引流；Root→VPN 先确认快照还原再 prepare/Builder。Always-on 按 App 所选模式，不建 Root 版 VPN；通知 ALWAYS_ON_VPN_CONFLICT，指引关闭 Always-on 与“屏蔽未使用 VPN 的连接”，不能声称可绕过系统 lockdown。

系统通知由原生（无 Flutter 时用不创建 VPN 的原生组件/受保护 receiver）发布；App 横幅/弹窗由 Flutter。通知“停止”不依赖引擎。不得仅靠持久通知假定系统会启动组件：冷启动通知链路待实测 W4。

## 5. 开机自启与文件布局

唯一薄入口 `/data/adb/service.d/flclash-root.sh`（root:root 0700），只定位固定 runtime、调用 `bootstrap.sh boot`、缺 runtime 时删除自身；无配置/密钥、无规则逻辑。其创建/替换/删除是 runtime 目录外唯一项目文件操作。标准模块打包为 ADR 备选，首版不用。

下列为 **root 侧**文件，基址 `R=/data/adb/flclash-root/`；App 既有私有设置/缓存仍属 App，root 核心不依赖它们，运行时资产、配置、日志、临时文件（TMPDIR）、状态仅在 R，系统包/网络状态只作探测。目录 root:root 0700，文件 0600、可执行文件 0700，禁止可写软链接和任意路径 API。

| 相对 R 路径 | 内容/所有者 |
|---|---|
| `bin/root-agent`、`bin/root-core`、`bin/watchdog`、`bin/root-ctl` | 按 ABI 安装、校验内置 SHA256 的固定程序；PID 含启动时间，按精确 PID 终止。root-ctl 仅供固定脚本调用。 |
| `scripts/bootstrap.sh`、`scripts/control.sh`、`scripts/cleanup.sh` | POSIX sh、固定参数，网络操作由固定程序/受限脚本执行。 |
| `config/manifest.json`、`config/config.yaml`、`config/assets/` | 最近有效配置的完整自足副本、provider/规则/geo 资源、digest/version/appUid；不靠开机解密 App 私有数据。 |
| `state/settings.json`、`state/state.json` | 意图/自启设置、§6 快照；原子 temp+fsync+rename，schemaVersion=1。 |
| `state/baseline.json`、`state/undo.jsonl` | 启动前快照及资源 undo journal，先于网络改动持久化。 |
| `run/core.sock`、`run/*.pid`、`run/agent.heartbeat`、`run/watchdog.heartbeat`、`run/owner.lock` | root 私有 Unix socket、PID+startTicks、单调时钟心跳、独占锁；锁不能只以 PID 文件是否存在判断。 |
| `logs/{agent,core,watchdog,boot}.log`、`responses/`、`tmp/` | 脱敏滚动日志各 2×1MiB；溢出响应、临时导入；清理均限定本目录。 |

脚本调用契约：`bootstrap.sh boot` 校验安装/授权/配置/开关后确保 agent+watchdog 唯一；`bootstrap.sh app --request-id UUID` 只启动/接入管理面，**不隐含接管**；`control.sh start|stop|status|reload --request-id UUID` 通过 socket 发 §6 命令，不拼 shell 输入；`cleanup.sh --reason disable|uninstall|recovery|residue --session UUID` 持锁按 journal 还原，disable/uninstall 完成后删除入口与 R、自退出。参数不符 exit 64；成功 exit 0，失败 exit 1，stdout 仅一条 §6 响应 JSON，日志入文件；boot 不把长驻进程挂在 service.d 前台。全部脚本 POSIX sh、`shellcheck -s sh` 零报错、重复执行幂等。

boot 不启动 App/Flutter：仅 rootTunEnabled && autostartEnabled 才提交本次 boot 的启动意图，不受上次仅 proxyStop 影响；同一 boot 重复入口不重复提交。等待系统包服务/用户解锁/网络，每 2s 重查，解锁后最多留 50s 等依赖 + 10s 启动预算。任何规则写入前已有可用配置、授权证据和看门狗；不可读/不可用保持直连，落 AUTOSTART_FAILED 或 AUTOSTART_ROOT_REVOKED。授权管理器撤权后的开机有效性检查是 W3 发布门槛，不能因 service.d 自带 root 而跳过。

watchdog 每 **10s** 调包管理服务并精确比较完整包名 `com.follow.clash.root`，同时检查 `/data/data/com.follow.clash.root`；连续两次确认完整包名不存在且目录不存在才判卸载，查询失败/升级期间不当成卸载。检测 ≤20s + 清理 ≤3s，留余量满足 60s。官方版 `com.follow.clash` 被卸载永不触发。下次 boot 重做同一检查，覆盖卸载无回调；卸载后删入口、R、规则/TUN并退出。pm/目录冲突结果（含保留数据卸载）见 W5。

`stop(reason=proxyStop)` 仅停止代理、恢复网络，保留 Root 模式/自启设置及监护；`stop(reason=disable|switchToVpn)` 关闭 Root 功能和自启，清理 R。单独 `setAutostart(false)` 删除入口，下次开机不接管，不中断当前代理；运行时卸载监护仍需保留。关闭后日志先通过 socket 取回 App 缓存再删除 R。每次启用从 APK 重装 runtime；升级原子替换版本，重复 boot/App attach 只接入已运行实例，不能重建 TUN/中断连接。

## 6. 接口契约 v1（Flutter mock 基准）

### 6.1 Dart ↔ Kotlin

`MethodChannel('com.follow.clash/root_tun')`、`EventChannel('com.follow.clash/root_tun/events')`，即 `$packageName/root_tun`、`$packageName/root_tun/events`；StandardMethodCodec，参数/结果为 Map/List/标量，**不套 JSON 字符串**。下面 JSON 是等价 mock 数据。未知可选字段忽略，必填字段/枚举不符是协议错误；所有时间为 UTC epoch 毫秒，null 必须明确传递。

Snapshot 必填字段及类型（所有方法/事件共用）：

| 字段 | 定义 |
|---|---|
| `schemaVersion`, `epoch`, `seq`, `intentRevision` | int=1；String 会话域（重装 runtime/重启生成新域）；非负 int 状态序号与最新意图版本。新域必须完整重置本地镜像。 |
| `state` | `disabled / awaitingAuth / starting / running / recovering / stopping / failed / degraded`。 |
| `rootManager` | `magisk / kernelsu / apatch / none / unknown`；none 无 su，unknown 检测未定或发现其他管理器，结合错误码区分。 |
| `authStatus` | `unknown / notGranted / granted / denied / revoked`；检测中不伪造已授权。awaitingAuth 仍是 notGranted。 |
| `mode`, `rootTunEnabled`, `autostartEnabled` | mode=`rootTun / vpn / off` 为选中的模式，非 running 标志；两 bool 为功能设置。rootTunEnabled=false 时自启必须 false。 |
| `lastErrorCode`, `lastErrorAt`, `warnings` | String?（仅附录 B）、int?；当前提示码 String[]。失败码保留到下次启动/用户确认；PRIVATE_DNS_STRICT、ALWAYS_ON_VPN_CONFLICT 仅在冲突存在时留 warnings；信息码只发事件。 |
| `authDeadlineAt`, `startedAt`, `updatedAt`, `stale` | int?（仅 Magisk awaitingAuth 有截止）、int?（本次代理开始时间）、int、bool；stale=true 表示 root 状态尚未核对，不得据缓存执行破坏性操作。 |

统一返回 `Result<T>={ok:bool,data:T|null,error:Error|null}`；成功 error=null，失败 data=null。`Error={code:String,details:Map,retryable:bool}`，业务 code 只用 PRD 附录 B。变更命令成功 data 为 `Ack={requestId:String,intentRevision:int,disposition:accepted|coalesced,snapshot:Snapshot}`，只确认意图入列，**不表示运行成功**；最终结果以状态事件/getState 为准。requestId 为调用方 UUID；相同 ID/参数重试幂等，改参数重用 ID 为 INVALID_ARGUMENT。过期任务不得改变最新意图，迟到 Ack 按 revision 丢弃。

| 方法 | 参数（无参数传 `{}`） | data / 时间上限 | 可能业务错误码或后续事件码（除另注均附录 B） |
|---|---|---|---|
| `getState` | `{}` | Snapshot，≤1s；本地镜像立即答复并异步核对，不触发 su | 无业务失败；当前错误在 Snapshot |
| `detectRoot` | `{}` | Snapshot，≤2s；无弹窗，只检测管理器/系统/已有授权，不启动 | ROOT_NOT_FOUND、ROOT_MANAGER_UNSUPPORTED、ANDROID_VERSION_UNSUPPORTED；返回 ok=true 的 degraded 快照并发事件 |
| `recheckRoot` | `{requestId}` | Ack ≤1s，检测 ≤2s | 同上；awaitingAuth 的 KSU/APatch 未获权保持原状并发 ROOT_GRANT_NOT_DETECTED；已获权且有未取消启动意图则 starting；单纯 degraded 检测恢复只到 disabled |
| `requestAuth` | `{requestId}` | Ack ≤1s；创建启动意图，与 start 共用授权流程 | Magisk：ROOT_PERMISSION_DENIED / ROOT_PERMISSION_TIMEOUT；KSU/APatch：ROOT_GRANT_REQUIRED_IN_MANAGER，不倒计时；前提不足为 detectRoot 三码 |
| `start` | `{requestId}` | Ack ≤1s；选择 Root 模式并启用；已有授权后 starting ≤10s（含模式互斥及自检） | 授权诸码；TUN_DEVICE_UNSUPPORTED、TUN_CREATE_FAILED、NETWORK_RULES_APPLY_FAILED、DNS_TAKEOVER_FAILED、CORE_START_FAILED、START_TIMEOUT、MODE_SWITCH_FAILED；MODE_SWITCHING/ALWAYS_ON_VPN_CONFLICT/PRIVATE_DNS_STRICT 为提示 |
| `stop` | `{requestId,reason}`；reason=`proxyStop / disable / switchToVpn / cancelAuth / acknowledgeFailure` | Ack ≤1s，清理 ≤3s；cancelAuth 取消待授权意图并回 disabled；acknowledgeFailure 仅 failed→disabled；disable 连同自启/R 清理；switchToVpn 只完成 Root 清理，VPN 的启动仍走既有 ServiceState | CLEANUP_FAILED、MODE_SWITCH_FAILED；该 reason 的清理目标已满足才 coalesced，disabled 不代表 R 已删除 |
| `setAutostart` | `{requestId,enabled:bool}` | Ack ≤1s，文件事务 ≤3s；成功状态事件更新开关；不隐含 start | AUTOSTART_FAILED、ROOT_PERMISSION_REVOKED；仅 Root 功能已启用且获权可设 true，否则参数/前提冲突，不能偷偷授权 |
| `cleanupResidue`（P1） | `{requestId}` | Ack ≤1s，清理 ≤3s；运行中通过停止流程，按保存 journal 清理，关闭功能/自启 | CLEANUP_FAILED；尚未交付时 MethodNotImplemented，Flutter 隐藏入口 |
| `getLogs` | `{cursor:String\|null,limit:int}`；默认 null/200，范围 1..500 | ≤2s，`{sourcePath:String,entries:[{cursor:String,at:int,level:debug\|info\|warn\|error,code:String\|null,message:String}],nextCursor:String\|null,eof:bool}`；按时间升序；失效游标从现存最早日志开始 | 读取失败为技术错误 CORE_ERROR（details.phase=readLogs），无新增业务码；目录已正常删除则成功空列表；sourcePath 仅诊断，Flutter 不直接读 root 文件 |
| `exportDiagnostics` | `{requestId}` | 原生总耗时 ≤15s（root 采集 ≤10s + 打包），Dart 等待上限 **20s**；`{path:String,sizeBytes:int,mimeType:"application/zip"}`；不改变状态、不产生 Ack/intentRevision，详见下方「exportDiagnostics 契约」 | 无新增业务码；打包/写文件失败为技术错误 CORE_ERROR（details.phase=exportDiagnostics）；无 root/未授权/超时仍成功返回，缺失项在 zip 内注明 |

#### exportDiagnostics 契约

用途：首个真机环境只靠 App 内「导出诊断日志」取证（ADR-0001），因此 N1 起即为必备方法，Flutter mock 与原生实现都以本节为准。

- **请求**：`{requestId:String}`（UUID）。同一 requestId 采集进行中重复调用，复用同一任务并返回同一结果；不同 requestId 并发时串行执行。
- **成功**：`Result.ok=true`，`data={path:String,sizeBytes:int,mimeType:"application/zip"}`。`path` 是 App 私有目录 `cache/diagnostics/` 下的绝对路径（文件名 `flclash-root-diag-<UTC 时间>.zip`），只保留最近 3 份；`sizeBytes` 为最终 zip 字节数，上限 20MiB，超限时截断大日志并在 manifest 注明。
- **失败**：统一 `Result/Error`：`ok=false,data=null,error={code:"CORE_ERROR",details:{phase:"exportDiagnostics",reason:"zipFailed|ioError|busy"},retryable:true}`。不新增 PRD 业务码，不写 lastErrorCode。**root 不可用、未授权、单项命令失败或总超时都不算失败**：照常返回 zip，缺失/超时项在 `manifest.json` 中标注。
- **Kotlin 侧**：所有 root 项在 **一次 su 调用** 中由一个固定 POSIX sh 采集脚本完成（不拼接用户输入），**总超时 ≤10s**；超时即终止该 su 进程，已写出的部分照常打包。脚本把各项输出写到 `R/tmp/diag-<requestId>/`，结束后以 App UID 可读方式交给 Kotlin，Kotlin 读取后删除临时目录，再合并 App 侧信息、脱敏并打包 zip。禁止每项单独调用 su。
- **Flutter 侧**：调用后等待上限 **20s**（§6.1 通用的 getter 3s / 命令 2s 对本方法不适用），拿到 `path` 后用系统分享面板（`share_plus` 等）发出文件，或保存到用户选择的位置；Flutter 不读 root 文件，只处理返回的 App 私有文件。超时提示「导出超时，请重试」，可用新 requestId 重试。
- **脱敏**：token/secret/password/私钥/订阅 URL 查询串、代理节点服务器地址与 UUID 一律替换为 `[redacted]`；zip 内不含 `config.yaml` 原文，只含脱敏后的摘要。

zip 内容（每项一个文件；`manifest.json` 记录每项的命令、exit code、耗时、是否超时/跳过）：

| 文件 | 内容 |
|---|---|
| `manifest.json` | requestId、导出时间（UTC 毫秒）、App 版本/构建号/applicationId、APK ABI、各项采集结果 |
| `system.txt` | 机型（`ro.product.model`/`ro.product.manufacturer`）、Android 版本与 SDK（`ro.build.version.release`/`ro.build.version.sdk`）、**安全补丁**（`ro.build.version.security_patch`）、`ro.build.fingerprint`、`getenforce` |
| `kernel.txt` | `uname -a`、**PAGE_SIZE**（`getconf PAGE_SIZE`）、`/proc/version`、是否支持 `/dev/net/tun` |
| `root.txt` | 识别到的 root 管理器与 **KernelSU 版本**（`ksud -V` 及内核侧版本号；Magisk 为 `magisk -V`/`magisk -c`，APatch 为对应版本），su 路径，授权状态 |
| `state.txt` | 当前 Snapshot、`R/state/` 下状态文件、owned 资源清单、各进程 PID 与 startTicks、心跳文件 |
| `network.txt` | `ip -4/-6 rule show`、`ip -4/-6 route show table all`、`ip link`/`ip addr`（含 flcrtun0）、`iptables-save`/`ip6tables-save`（含 FCR_OUTPUT）、私人 DNS 设置、`dumpsys connectivity` 中 VPN/lockdown 相关行 |
| `baseline/` | 启动时保存的 `baseline.*` 快照 |
| `restore-diff.txt` | 关闭/清理后与 `baseline.*` 的差异（规范化 iptables 计数器与注释后比较，为空即“与开启前一致”）；尚未关闭过则注明 |
| `avc.txt` | SELinux 拒绝记录：`dmesg` 与 `logcat -d -b all` 中 `avc:` 相关行（最近 2000 行内过滤） |
| `logs/` | `R/logs/` 下 runtime/supervisor/watchdog/core/boot 日志（脱敏、各取末尾 1MiB）、mihomo 校验日志 |
| `app.txt` | App 侧 RootTun 日志与最近 256 条状态事件 |


同步业务前提失败（如 start 未检测到 root）返回 ok=false 并按状态机更新快照；授权拒绝/实际启动失败在 Ack 之后用事件报告。参数非法或状态不允许时，用 `PlatformException('INVALID_ARGUMENT',…,details)`；setAutostart(true) 在功能关闭/尚未授权时分别 details.reason=ROOT_TUN_DISABLED/AUTH_REQUIRED，已确认撤权则按表返回业务错误。通道/IO不可用用 `PlatformException('CORE_ERROR',…,{'phase':…})`，技术错误不加入 PRD 用户错误码，也不写 lastErrorCode；Flutter 捕获后重新 getState，不把通信失败当作 disabled。所有方法后台 IO/su/socket；只有 EventSink/Activity 交互回主线程。Dart RPC 等待上限 getter 3s、命令 2s，**超时不取消命令**；用同 requestId 重试或 getState。授权/启动/恢复计时归原生/root 单调时钟，取消须 stop(cancelAuth)。

正常快照、命令及结果示例：

```json
{"ok":true,"data":{"schemaVersion":1,"epoch":"boot7-session1","seq":42,"intentRevision":8,"state":"running","rootManager":"magisk","authStatus":"granted","mode":"rootTun","rootTunEnabled":true,"autostartEnabled":true,"lastErrorCode":null,"lastErrorAt":null,"warnings":[],"authDeadlineAt":null,"startedAt":1792713600000,"updatedAt":1792713601000,"stale":false},"error":null}
```

```json
{"method":"start","arguments":{"requestId":"7fb480b6-08a9-4113-8505-912671462d51"}}
{"ok":false,"data":null,"error":{"code":"ROOT_NOT_FOUND","details":{"phase":"detectRoot"},"retryable":false}}
```

成功 Ack 示例（不能只返回布尔值）；KSU/APatch mock 依次发 awaitingAuth（authDeadlineAt=null）、停留 >30s、未授权 recheck、取消/授权成功四组场景：

```json
{"ok":true,"data":{"requestId":"7fb480b6-08a9-4113-8505-912671462d51","intentRevision":9,"disposition":"accepted","snapshot":{"schemaVersion":1,"epoch":"boot7-session1","seq":44,"intentRevision":9,"state":"starting","rootManager":"magisk","authStatus":"granted","mode":"rootTun","rootTunEnabled":true,"autostartEnabled":true,"lastErrorCode":null,"lastErrorAt":null,"warnings":[],"authDeadlineAt":null,"startedAt":null,"updatedAt":1792713603000,"stale":false}},"error":null}
```

EventChannel `listen` 参数 `{schemaVersion:1,epoch:String|null,afterSeq:int}`。事件必有 `schemaVersion,epoch,seq,kind,requestId,code,at`；requestId/附录 B code 可 null。kind=`snapshot` 时带完整 `snapshot`；kind=`delta` 时带 `baseSeq:int,changes:Map`，changes 只放改变字段（含显式 null），可只发 code 不改 state。seq 每个事件递增，状态/错误都须 ≤5s 送达；日志/流量不挤占此流。

```json
{"schemaVersion":1,"epoch":"boot7-session1","seq":43,"kind":"delta","baseSeq":42,"requestId":null,"code":"CORE_CRASHED_RECOVERING","at":1792713602000,"changes":{"state":"recovering","lastErrorCode":"CORE_CRASHED_RECOVERING","lastErrorAt":1792713602000,"updatedAt":1792713602000}}
```

App 中途接入：**先 getState 渲染，再 listen 携带 epoch/seq**。原生保留最近 256 事件补发；无可补历史、epoch 不同或首次订阅，先发新的完整 snapshot，保证两步间不丢变化。旧 seq 丢弃，baseSeq 不连续就 getState+重订阅；缓冲溢出用完整 snapshot 合并恢复，不静默丢错误。引擎 detach 只退订，不停止开机核心；attach 不重设配置/不重复 start。getState 的 warnings/lastError 可恢复离线提示，不重放弹窗风暴。

附录 B 的其他运行码也经同一事件契约：ROOT_PERMISSION_REVOKED / AUTOSTART_ROOT_REVOKED、CORE_RECOVERED / CORE_RECOVERY_FAILED / CORE_CRASH_LOOP、LAST_SESSION_ABNORMAL_EXIT、PRIVATE_DNS_AUTO_TAKEN_OVER、AUTOSTART_FAILED、CLEANUP_FAILED；不增添 TunState。文案/位置直接复用 PRD 附录 B 的 27 码，原生通知和 Flutter 各自按 code 映射，不能根据中文 message 判断逻辑。

### 6.2 核心数据桥（保持 Dart 协议）

`com.follow.clash/core.invokeMethod` 的参数仍是 **CoreMethodCall JSON String**，返回仍是完整 CoreMethodResponse 的 UTF-8 字节；Dart `CoreLib` 不知道进程位置。`ServicePlugin` 按已选后端调用 gomobile 或经 root socket 转发；`service.init/syncState/shutdown` 在 Root 后端分别接入/同步展示设置/退订，shutdown 不隐含杀核心。切模式由原生冻结旧后端请求并结束旧 pending，再接新后端；不同时开两套监听端口。Core 方法中的 listener/shutdown 不得越过 ServiceState/agent 独立改 Root 意图，需后端适配成 agent 操作，保留原返回类型。

`CoreMethodCall={id?:String,method:String,arguments:any}`；`CoreMethodResponse={id?:String,result:any,error?:{code,message,details},file?:String}`；error 为空/缺省时成功。数据不二次 JSON 编码。例（速率 B/s、累计 B、connections/日志沿用 `core/protocol.go`）：

```json
{"id":"17","method":"getTraffic","arguments":false}
{"id":"17","result":{"up":1024,"down":4096}}
{"id":"18","method":"getTotalTraffic","arguments":false}
{"id":"18","result":{"up":2048,"down":8192}}
{"id":"19","method":"getConnections","arguments":null}
{"id":"19","result":{"downloadTotal":8192,"uploadTotal":2048,"connections":[],"memory":10485760}}
{"id":"20","method":"startLog","arguments":null}
{"id":"20","result":true}
{"method":"message","arguments":[{"type":"log","data":{"LogLevel":"info","Payload":"root core ready"}}]}
```

最后一条为既有核心日志事件（`core/log.go`、mihomo log.Event、`lib/models/common.dart::Log`，大写键名不能改）；Kotlin 按既有 `com.follow.clash/service` 方法 `event` 发送此 JSON 的 byte[]，保留单事件/批事件解码。socket 断连 pending 返回原协议 `error.code=transport_disconnected`，不伪造零流量/空连接；核心本身继续运行并重连接管面。Core 错误码命名空间与 PRD 用户错误码分开。

Root home 在 R，不能把 root `file` 路径交给 Dart `resolveSpilledResponse`：Kotlin 经受限 `readResponse(responseId)` 分块取回，验证 basename/会话/长度后在 App 既有 `<home>/responses/` 生成镜像并返回原 file envelope，消费后两端删文件；禁止任意路径读写/删除接口。配置资产由 Kotlin 从本 App 私有目录分块 stage 到 R，重写 home/profile 路径；Dart 请求/响应结构不变。启动/配置提交必须生成完整有效 manifest，boot 不依赖 Flutter 重新生成配置。

### 6.3 Kotlin ↔ root agent / core

App-facing Unix stream socket 地址 **`@com.follow.clash.root.control.v1`**（首字节 NUL，抽象命名空间，不是 `/data/adb` 下的文件）。选择抽象 socket 避免要求 untrusted_app 穿越 `/data/adb`；SELinux stream_connect 仍为 W1。agent 私有监听 `R/run/core.sock`（0600，root-core 主动连接），复用桌面方向；此连接断开不退出核心。watchdog 通过相同控制面/独占锁接管。

每次 accept 在读 payload 前校验 **SO_PEERCRED**：App 面只放行安装记录的 `com.follow.clash.root` **完整 UID**；UID 0 仅放行已登记 PID+startTicks 的 agent/watchdog/core，以及 peer PID 的 executable 路径/摘要匹配只读安装清单的 root-ctl；其他 UID（包括官方版）拒绝、关闭并记录 UID/PID。Kotlin 验证对端 UID=0；root-core 同样验证 agent 身份。不得信任 JSON 的 uid、包名、客户端自报 PID，socket 名和 chmod 不能代替认证；不靠放开全局 SELinux 保证连接。其他 App 即使知道地址也无执行入口。

所有 socket 使用 `uint32 little-endian length + UTF-8 JSON`（与现有 core/server.go 一致），单帧 ≤64MiB，控制消息 ≤64KiB；无换行分隔，读满长度，异常长度/格式拒绝并断连；各连接写串行，id 关联乱序响应。连接/握手 2s，status 1s，命令接收 1s；长任务先 Ack 后事件。UI 未订阅时日志有界落盘，不阻塞网络/生命周期。

控制请求 `{v:1,id:String,method:String,params:Map}`；响应 `{v:1,id,ok,result:any|null,error:Error|null}`，成功 error=null，失败 result=null，业务 Error 同 §6.1；技术错误仅 INVALID_ARGUMENT/CORE_ERROR，不映射 PRD 文案。事件 `{v:1,event:"rootTun"|"core",payload:any}`，分别承载 §6.1 状态事件或原 CoreMethodCall(message)。固定方法如下，未知方法/参数拒绝，不提供 shell 命令或任意文件操作：

| method | params / result |
|---|---|
| `start` | `{requestId,source:app\|boot\|tile\|notification\|alwaysOn}` → Ack；只使用已提交 manifest，root agent 分配 intentRevision、最新意图胜出。 |
| `stop` | `{requestId,reason}`，reason 同 §6.1 或 `revoked\|recoveryFailed\|crashLoop\|uninstall`（后四者仅原生/root 内部）→ Ack。 |
| `status` | `{}` → 完整 Snapshot；不得仅凭 state.json 认定 running，核对 PID/心跳/资源。 |
| `reload` | `{requestId,configRevision:String,sha256:String}` → Ack；仅应用已 stage 且验证完成的版本，失败回到上个有效配置；路由变更也须更新 journal，不能用默认空配置继续宣称 running。 |
| `setAutostart` / `cleanupResidue` / `getLogs` | 参数/返回语义同 §6.1；不得接受客户端自定义目录。 |
| `core.invoke` | `{call:CoreMethodCall}` → 原 CoreMethodResponse，id 双层独立；Kotlin 解包再发原 JSON byte[]。 |
| `subscribe` | `{epoch,afterSeq,coreEvents:bool}` → `{subscribed:true}`，随后事件；rootTun 支持补发，core 事件沿用已有有界队列策略。 |
| `stage` | `{requestId,configRevision,kind:manifest\|config\|asset,assetId:String,offset:int,total:int,sha256:String,dataBase64:String,commit:bool}` → `{nextOffset:int,committed:bool}`；每块解码 ≤48KiB、顺序上传；assetId 只来自 APK/已验证 manifest 固定清单，≤256MiB/文件、总额≤512MiB，digest 完整校验/原子 commit，禁止路径穿越与符号链接。重复块校验一致后幂等；仅 staging 不接管。 |
| `readResponse` / `releaseResponse` | 前者 `{responseId:String,offset:int,limit:int}`（limit≤49152）→ `{dataBase64,total,eof}`；后者 `{responseId}`→`{released:true}`；responseId 仅本会话 response manifest 中对象，非文件路径，连接归属 UID 校验。 |

示例：

```json
{"v":1,"id":"rpc-1","method":"start","params":{"requestId":"7fb480b6-08a9-4113-8505-912671462d51","source":"app"}}
{"v":1,"id":"rpc-2","method":"core.invoke","params":{"call":{"id":"17","method":"getTraffic","arguments":false}}}
{"v":1,"id":"rpc-2","ok":true,"result":{"id":"17","result":{"up":1024,"down":4096}},"error":null}
```

state.json 是 §6.1 **完整 Snapshot** 加内部字段 `sessionId:String,bootId:String,pids:{agent,core,watchdog},health:{lastHealthyBootMs:int,recoveryDeadlineBootMs:int|null},crashBootMs:int[],configRevision:String`；每个 pid 对象 `{pid:int,startTicks:int}`。settings.json 示例：`{"schemaVersion":1,"mode":"rootTun","rootTunEnabled":true,"autostartEnabled":true,"appUid":10345,"desiredRunning":true,"intentRevision":8,"lastRequestId":"…"}`。watchdog 心跳示例：`{"schemaVersion":1,"pid":5678,"startTicks":12345,"bootId":"…","bootMs":60000,"sessionId":"…"}`。墙上时钟仅展示，期限/5min 崩溃窗口用 boot 单调时间，重启清空崩溃窗口；旧 boot/PID 不能据此杀新进程。

manifest.json 必填 `{schemaVersion:1,configRevision:String,appUid:int,rootManager:String,coreSha256:String,configSha256:String,assets:[{assetId:String,sha256:String,size:int}]}`。baseline.json 必填 `{schemaVersion:1,sessionId,bootId,capturedAt:int,ipRules4:List,ipRules6:List,routes4:List,routes6:List,iptables:String,ip6tables:String,nft:String|null,links:List}`；IP/link 项为结构化完整属性，iptables/ip6tables 为 save 格式。undo.jsonl 每行 `{schemaVersion:1,sessionId,step:int,kind:ipRule|route|iptables|ip6tables|link,before:any|null,after:any,applied:bool}`，动作由 kind 的固定 handler 实现，不能存任意 shell 命令；applied=false 的未确认步骤也按实际资源核对回滚。nft 首版不用，若采用先扩充 journal kind 与验收。

agent 正常为唯一写者，watchdog 发现失联后拿 owner.lock、作代际检查、恢复 agent 或执行 journal；心跳失效但进程仍持锁时，先核验 PID+startTicks 并终止该已记录进程，不无限等锁。接管先增加 intentRevision 防止旧进程回写；无残留时 Kotlin 可直接构造 disabled 快照，不为 getState 重建 R。

### 6.4 实现偏差记录（N1 / #22 相对本文的偏差）

N1 的目标是先出一个可手测的 debug APK，用来验证方案 B 是否可行。以下偏差已知并且已经登记；每条都写明了原因、风险和验收条件。偏差没有消除之前，不得在文档或 Release 里宣称已符合 §6.3 / §4。

**偏差 1：控制通道用 127.0.0.1 TCP 随机端口加 token，没有用 §6.3 的抽象 socket**

- **现状**：Kotlin 直接连接 root 侧 mihomo 的 `external-controller`。
  - 监听地址是 `127.0.0.1:<随机端口>`。每次启动时用 `ServerSocket(0)` 选一个空闲端口，写入 `R/config/controller.port`。
  - 鉴权用 HTTP `Authorization: Bearer <token>`。token 是每次启动生成的随机 UUID，作为 mihomo 的 `secret`。
  - Kotlin 通过 su 读取端口和 token。
  - 所有入站代理端口（port、socks、mixed、redir、tproxy）都设为 0，`bind-address` 是 127.0.0.1。
  - 没有 root-agent，也没有 `@com.follow.clash.root.control.v1` 和 SO_PEERCRED 校验。
- **原因**：
  - 复用 mihomo 现成的控制接口，N1 不需要先写 root-agent 和 socket 服务端，可以尽快在真机上验证建 TUN 和跑通流量。
  - 抽象 socket 在 untrusted_app 和 su 域之间的 SELinux `stream_connect` 还没有在 Android 17 / KernelSU 上核实（W1），先用 TCP 回环避开这个未知项。
- **风险**：
  - 本机任何 App（任意 UID）都能连上这个端口，也能通过扫端口发现它。服务端只认 token，不认调用方 UID。
  - token 一旦泄露（日志、诊断包、内存转储），其他 App 就能读取连接或流量信息、切换节点、修改规则，甚至让核心停止服务。
  - 连接洪泛有可能拖垮控制面。
  - 流量只在回环上传输，不出设备。
- **缓解**：
  - 只绑定 127.0.0.1，不监听 0.0.0.0 或 ::。
  - 端口每次启动随机选取，token 是 122 bit 随机数。
  - 不开放任何入站代理端口。
  - `R/config` 仅 root 可读（0600 / 0700）。
  - 日志和诊断导出对 token 脱敏。
  - Kotlin 的连接和读取超时都是 300ms。
- **验收条件**（每个手测包都要满足，用诊断包证明）：
  - ① `ss -ltnp` 或 `/proc/net/tcp*` 显示控制端口只监听在 127.0.0.1，其余入站端口都不存在。
  - ② 不带 token 或 token 错误的请求返回 401。
  - ③ 两次启动的端口和 token 都不相同。
  - ④ 日志和诊断 zip 里搜不到 token 原文。
  - ⑤ `R/config` 的属主和权限符合上面的缓解要求。
- **去留**：发布 GitHub Release 之前，必须二选一，由项目经理评审：
  - 迁移到 §6.3 的抽象 socket 加 SO_PEERCRED（或者同等的按 UID 认证）；
  - 修订 ADR-0001，正式接受 TCP 加 token，并补上调用方 UID 校验的替代方案。

**偏差 2：崩溃恢复期间存在直连窗口**

- **现状**：`runtime.sh supervise` 发现 core 死亡后，按 `cleanup → install_rules → launch_core` 的顺序恢复。
  - 第一步就把规则全部拆掉，所以从 cleanup 到新 core 起来、规则重新装上的这段时间里，流量绕过代理直连。
  - 这段时间内 DNS 和 IPv6 防漏规则也一起失效。
  - 窗口长度通常有几秒，最长可到 core 启动超时。
  - 这与 §4“先保留接管规则；不能恢复再拆规则 fail-open”不一致。
- **风险**：恢复期间，各 App 的真实 IP 和 DNS 查询会直接发出，违背 US-05 / US-08 的“不泄露”要求。不过网络始终可用，不会断网。
- **验收条件**：
  - 手测包允许存在这个窗口，但 supervisor 日志必须记录窗口的开始和结束时间（单调时钟）与持续时长，诊断包里要能看到。
  - 30s 恢复预算和第 3 次 / 5min 熔断照常执行。
- **消除**：随 #25 一起修改，**合入 main 前必须完成**。目标行为：
  - 恢复期间保留接管规则和防漏规则，让流量 fail-closed，只重启 core。
  - 恢复失败时才执行 cleanup，fail-open 并进入 `failed`。

**偏差 3：诊断采集方式**

- **现状**：#22 现在按大约 17 次独立 su 调用采集诊断，每次超时 2s。
- **要求**：改为按上面的 exportDiagnostics 契约，一次 su 完成采集，总超时 ≤10s，返回 `{path,sizeBytes,mimeType}`。
- **完成时机**：在 #22 / #23 的返工里完成，不留到后续 PR。

**偏差 4：没有独立 root-agent 和 watchdog**

- **现状**：生命周期监督只有一个 sh 进程。
- **处理**：由 P0 后续项 #25 补齐，见 §10。

## 7. PRD P0 AC → 设计点 → 测试

范围含 US-01..17a 中所有 P0；US-12 与 US-16 AC4 为 P1，不混作 P0。

| PRD AC | 设计点 | 测试方式 |
|---|---|---|
| US-01 AC1/2/3 | root 核心自建 TUN、10s 自检、数据桥 | 浏览器代理站/连接页；ip link/addr UP；dumpsys 无本包 TRANSPORT_VPN |
| US-02 AC1；AC2 | 不调用 VPN；其他 VPN 共存记已知行为 | 状态栏/系统 VPN；spike 与官方版/另一 VPN 同跑，回填 R2，不据 AC2 否决首版 |
| US-03 AC1/2/3 | ≤3s 清理、journal/快照 | 前后全量规则/路由/网卡 diff，直连正常；连续开关 20 次 |
| US-04 AC1/2 | ServiceState 串行模式切换 | 两方向切换、starting 中取消/快速反向；只有一套接管，核对 MODE_SWITCHING |
| US-04 AC3/4/5 | 所有原生入口按选定模式；Always-on 提示 | 磁贴/快捷方式/无引擎回调；Always-on+lockdown，确认不建 VPN、提示设置入口 |
| US-05 AC1/2/3 | TCP/UDP 53 劫持与防漏/还原 | 指定任意 DNS、dnsleaktest；物理口抓包（核心配置上游单列）；停后 DNS 正常 |
| US-05 AC4/5 | 自动 REJECT 853；严格只提示 | A10/A15 私人 DNS 自动/严格抓包；自动退回 53、仅日志；严格不拦853、横幅/入口，AC1/2 豁免 |
| US-06 AC1/2 | 标记/物理出口防回环 | WG/Hysteria2/VLESS，空闲10min平均<10KB/s及CPU，下载100MB比物理/TUN量级 |
| US-07 AC1/3 | 独立 watchdog、≤30s、3次/5min 熔断 | kill -9 核心；App+agent+core 同杀而 watchdog 独活；恢复成功/失败与第3次崩溃，抓时间/规则 |
| US-07 AC2 | 会话与网络核对 | 强停后重开，LAST_SESSION_ABNORMAL_EXIT；不误停仍运行的 root 核心 |
| US-08 AC1/2 | IPv6 业务阻断、停后还原 | 双栈/IPv6-only站，抓物理口排除必要NDP；无业务直出，停后IPv6直连恢复 |
| US-09 AC1a | Magisk 弹窗30s | 矩阵逐项授权、启动、DNS、停止、自启 |
| US-09 AC1b/1c；US-11 AC2b | KSU/APatch 管理器授权等待 | 无弹窗、停留>30s、不授权recheck保持、取消回disabled、授权后10s内running |
| US-09 AC2；US-10 AC1/3/4 | degraded 原因及重新检测 | 不支持管理器/无root/低于A10，置灰可点说明；满足前提后disabled |
| US-10 AC2 | VPN 后端保持原样 | 无root对照组跑原VPN/原分应用代理回归 |
| US-11 AC1/2/3 | 拒绝3s内失败、超时30s、撤权清理 | Magisk拒绝/不操作；三家运行中及开机撤权；规则清空、分方案指引/通知 |
| US-13 AC1/2/3/4 | service.d 独立启动、完整配置、POSIX | 重启解锁后60s内代理且不打开App；恰好1入口；断网/配置不可读无断网；shellcheck |
| US-14 AC1/2/3 | 文件原子替换、单实例 | 自启开关各10次；重复脚本/App接入不中断>3s；升级后唯一本版本入口 |
| US-15 AC1/2 | disable全清；自启关删除入口 | Root关后自启false/置灰、R无残留；仅关自启重启直连 |
| US-16 AC1/2/3/5 | 完整包名+目录、watchdog卸载检查 | UI卸载/pm uninstall无回调；≤60s直连；重启无残留；卸载官方版Root保持running |
| US-17a AC1/2/3 | Snapshot+增量、原生通知 | 全8态mock，首页/设置/通知≤5s一致；授权界面差异；先快照后订阅的丢包/补发/新epoch |
| NFR-01..14 | 时延/性能/安全/同步上游 | 20次启动P50≤5s/P95≤10s；吞吐≥VPN90%、1h耗电；24h及切网10s；异UID socket拒绝日志、LAN控制端口不可达、文件权限/无密钥/双包共存；DoD按团队规范 |

QA 矩阵：A10 Magisk；A12 Magisk/KernelSU；A14、A15 三家；各版本无 root 对照。Wi-Fi IPv4/双栈、移动数据；首版 IPv6 验防漏，分应用只回归 VPN，分身不承诺。每项交付至少两种 root 方案实测；P1 运行详情/残留清理另建测试，不替代 P0。

## 8. 可建 Issue 的任务拆分

编号为依赖占位，建 Issue 后换成实际号；分支均 `feature/<Issue号>-<描述>`。

| 负责人 / 任务 | 分支 | 依赖 / 验收产物 |
|---|---|---|
| Android N1：B 最小可用实现（建TUN/流量/SELinux/出口，含 App 内导出诊断日志） | `feature/N1-root-tun-core` | 无；小米 17 Pro Max（Android 17，KernelSU）真机经 debug APK 手测，以导出的诊断日志为证据，回填 W1/R2 |
| Android N2：root入口、agent、认证/数据桥/配置stage | `feature/N2-root-tun-backend` | N1；双ABI、Core契约兼容、异UID拒绝、重连不杀核心/不重建TUN |
| Android N3：网络事务、DNS/IPv6、回环与还原 | `feature/N3-root-tun-routing` | N1/N2；US-01..08、快照完全还原、失败注入 |
| Android N4：ServiceState接缝、授权/互斥/原生通知 | `feature/N4-root-tun-lifecycle` | N2；US-04/09/11、磁贴/通知/Always-on、W3/W4闭环 |
| Android N5：独立看门狗、service.d、升级/卸载清理、撤权检测（#25 #26 #28 #29） | `feature/N5-root-tun-autostart` | N2/N3/N4；US-07/13..16，shellcheck，W5闭环 |
| Flutter F1：通道模型、fake及断线/补发处理 | `feature/F1-root-tun-channel` | 本契约即可开工；八态/两授权流程/开机后attach，无进程位置假设 |
| Flutter F2：开关、状态/前提、错误码文案与设置入口 | `feature/F2-root-tun-ui` | F1、联调N4/N5；US-10/15/17a，附录B所有位置，系统通知不由Dart承担 |
| DevOps D1：双ABI（仅 arm64-v8a 和 x86_64）核心产物、包名/签名/CI | `feature/D1-root-tun-build` | N1/N2；applicationId独立、常量不变，Go/Kotlin/Flutter/Shell检查，构建v0.9.1-root.1，密钥仅Secrets |
| DevOps D2：上游同步与发布门禁 | `feature/D2-root-tun-release` | D1/Q2；一周内同步演练、非Root回归、GitHub Release清单；发布需项目经理转达审批 |
| QA Q1：矩阵、mock/故障/泄露与快照用例 | `feature/Q1-root-tun-test-plan` | 本文；表§7逐AC用例、Q1/Q2口径提交项目经理 |
| QA Q2：实机矩阵与长稳/升级验收 | `feature/Q2-root-tun-acceptance` | N3..N5/F2/D1/Q1；全部P0证据、≥两root方案、24h/性能报告及DoD |

## 9. 风险、PRD 疑问与待核实清单

PRD 疑问（提交项目经理，不自行改冻结范围）：**Q1** 网络切换/第三方改规则后，“与开启前快照一致”是否指还原本项目变更并保留当前系统网络，还是要求全局回到旧快照？静态验收仍按完全一致执行。**Q2** §5.1 要 failed 已直连，但同表允许清理失败进入 failed；F8/US-15 描述关闭自启清 runtime，而运行中的卸载监护又必须保留。草案暂定清理未完成保留 stopping+CLEANUP_FAILED，关自启仅删入口、关Root才删R，均需产品确认。

全部待核实项（不得用字段存在替代实机证明）：

| 编号 | 项目 / 负责与退出证据 |
|---|---|
| W1 | B 在小米 17 Pro Max（Android 17，KernelSU）真机上建TUN/流量；SELinux执行、netlink、SO_MARK及抽象socket连接；候选表/优先级/mark与netd冲突、WG/HY2/VLESS全出站防回环；A的跨域SCM_RIGHTS fd可用性。Android N1；保留命令/AVC/流量与还原证据，A只作比较不阻塞B。 |
| W2 | root INET_DIAG/procfs UID→包名在矩阵上的识别率、include-uid内核支持；M2包名过滤空实现不计已支持。Android N2+QA；当前 [process_linux.go](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/component/process/process_linux.go) 有Android回退逻辑，但权限/共享UID显示待测，不扩首版分应用范围。 |
| W3 | 三家无弹窗授权探测、运行中撤权≤5s及boot有效授权验证；KSU/APatch管理器入口兼容。Android N4/N5；不能以root daemon UID代替用户授权。 |
| W4 | 无App/引擎的系统通知与停止入口、Android后台限制/通知权限、私人DNS自动853回退及切换监听、DNS/IPv6防漏、开机解锁60s、切网10s。Android+QA；不借启动VpnService满足。 |
| W5 | 三家service.d实机时序、升级原子替换、pm查询/目录冲突与保留数据卸载判据、kill -9后watchdog仍活及全量还原≤3s。Android N5+QA；普通卸载≤60s为硬验收。 |
| W6 | US-02 AC2：其他VPN/官方FlClash并行及Always-on lockdown行为。Android N1+QA，按PRD R2回填，首版不承诺共存流量策略。 |

ADR 已采纳 B（待真机验证）：N1 在 KernelSU 真机上成功建 TUN 并跑通流量即视为验证通过；W1 其余项与 W2–W5 是开发/发布门槛，不能随 ADR Accepted 一并宣称通过。若真机验证不通过，ADR 改为 Superseded 并交项目经理评审，不直接切回违反 US-13 AC1 的原案 A。

## 10. P0 后续项（合入 main 前必须补齐）

经牛马CEO 确认：本轮（#22 原生、#23 Flutter）**先出可手测的 debug APK 验证方案 B**。下面 4 项 P0 拆到后续 PR 完成，但 **`feature/root-tun-*` 合入 main 之前必须全部完成并通过各自的验收标准**，否则不得合入。

| # | Issue | 内容 | 关联 AC |
|---|---|---|---|
| 1 | [#25](https://github.com/yuanjing-hash/FlClash/issues/25) | 独立看门狗：与 supervisor 之间没有父子死亡联动，每 1s 检查一次心跳，失联时接管或清理；同时消除偏差 2 的直连窗口 | US-07 AC1/AC3 |
| 2 | [#26](https://github.com/yuanjing-hash/FlClash/issues/26) | 卸载检测：每 10s 精确检查 `com.follow.clash.root` 和 `/data/data/com.follow.clash.root`，连续 2 次不存在就清理，并删除入口和 R；卸载官方版 `com.follow.clash` 永远不触发 | US-16 AC1/AC2/AC3/AC5 |
| 3 | [#28](https://github.com/yuanjing-hash/FlClash/issues/28) | service.d 自启：POSIX sh、幂等，等待 `sys.boot_completed` 后读取 `$R/config` 决定是否启动；Kotlin 的 `setAutostart` 只写入或删除自己的入口文件；`stop(proxyStop)` 保留自启 | US-13 AC1–AC4、US-14 AC1–AC3 |
| 4 | [#29](https://github.com/yuanjing-hash/FlClash/issues/29) | 授权撤销检测：App 侧每 ≤5s 做一次 su 探测，root 侧按管理器的授权记录判断；撤销后清理、关闭自启，报 `ROOT_PERMISSION_REVOKED` / `AUTOSTART_ROOT_REVOKED` | US-11 AC3 |

偏差 1（控制通道）的去留不在上面 4 项里，按 §6.4 的规定在发布前评审。偏差 3（诊断采集）在本轮返工中完成。

