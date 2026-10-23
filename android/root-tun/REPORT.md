# Android Root TUN 原生最小实现

分支 `feature/root-tun-native`，2026-10-23。仅修改当前 worktree，未 push。
这是供 Flutter 接入和真机联调的原生实现；**本机未产出 APK，不能据此宣称真机可用或完整 P0 验收通过**。

## 文件与行为

- `app/src/main/kotlin/com/follow/clash/root/`：有界、可取消的 su 执行；root 管理器/授权检测；协议模型；配置及资源安装；状态/请求仲裁；DNS 自检；通知；诊断导出。
- `app/src/main/kotlin/com/follow/clash/plugins/RootTunPlugin.kt`、`MainActivity.kt`：注册 MethodChannel/EventChannel；导出仅返回 ZIP，保存/分享由 Flutter 负责。
- `ServiceState.kt`：Root 入口仍由此持有；启动 Root 先取消并停止旧服务；Root 模式阻止原 VPN start；切回 VPN 必须先 `stop(switchToVpn)`。磁贴/快捷方式的启动/停止转交 Root 后端。
- `app/src/main/assets/root-tun/runtime.sh`：独立 su 后台监督进程。唯一写网络规则和启动核心的组件；PID 同时核对 startTicks 和 boot ID。崩溃后恢复，5 分钟第 3 次崩溃熔断；恢复失败清理规则；清理失败保持 stopping 并重试。
- `root-tun/build.gradle.kts`、`root-tun/build-core.sh`：Gradle 自动构建独立 mihomo，按 ABI 作为 `libroot_mihomo.so` 加入 generated jniLibs；保留可执行 ELF，不调用 System.loadLibrary。
- `settings.gradle.kts`、`app/build.gradle.kts`、manifest、XML/中英文资源：所有构建的 applicationId 为 `com.follow.clash.root`；namespace/两个 packageName 常量不改。仅 arm64-v8a/x86_64、useLegacyPackaging、非 VPN 前台服务；已移除 extractNativeLibs 和诊断 FileProvider。SAFE_MODE 返回 CORE_START_FAILED、retryable=false、reason=SAFE_MODE。
- `app/src/main/assets/root-tun/service.d.sh`：安装为 `/data/adb/service.d/flclash-root.sh`，后台等待 boot_completed，检查持久化开关和配置，同一 boot 只提交一次启动。
- `app/src/main/assets/root-tun/diagnostics.sh`：一次 su/sh 采集带分段标记的诊断，等待预算 9 秒（双流收尾最多再等 600ms）。
- `android/tests/app/root/`：su 转义/双流/超时/输出界限、状态枚举/空字段、DNS 响应校验、日志脱敏。

配置来源为 App `filesDir/config.yaml`，不是示例空配置。保留节点/规则/DNS，迁移本地 provider/geo 文件；路径限于 App filesDir，单文件 256 MiB、总额 512 MiB。select 组按 SharedState selected-map 排序，优先保留当前选中项。测试配置成功才引流。

强制 gVisor TUN、auto-route、auto-detect-interface、strict-route、any:53；不使用 VpnService fd。独占表 2022、pref 8990–9011、`flcrtun0`、FCR_OUTPUT；启动前整段查空。使用 routing-mark `0x40000000` + goto 越过接管区，未沿用 spike 的 UID 0 全体豁免。控制器只绑定随机的 127.0.0.1 TCP 端口并使用每次生成的 token；关闭其他入站和外部 UI。IPv6 业务在 OUTPUT 阻断，仅放行 loopback 和 NDP。私人 DNS 自动模式拒绝非核心 853，严格模式保留服务器、通过 warnings 提示。

原生确认 API、TUN UP/路由及来自 App UID 的 UDP/TCP DNS 应答后显示 running。关闭时 TERM 精确核心 PID，必要时 KILL；只清理已保留所有权的表/优先级/链/接口，不全局 flush/restore。发现未认领的冲突时拒绝删规则。运行时文件仅写 `/data/adb/flclash-root/`；App 自身状态缓存、分享 ZIP 仍在 App 私有目录。

## Flutter 契约

通道固定为 `com.follow.clash/root_tun` 和 `com.follow.clash/root_tun/events`，StandardMethodCodec 的 Map/List/标量，**不是 JSON 字符串**。所有可空字段显式返回 null。

| 方法 | 参数 | data |
| --- | --- | --- |
| getState | `{}` | Snapshot；仅本地镜像，不触发 su |
| detectRoot | `{}` | Snapshot；Magisk 不触发授权弹窗；KSU/APatch 探测 id |
| start / requestAuth | `{requestId: UUID}` | Ack，最终结果通过事件/getState |
| recheckRoot | `{requestId: UUID}` | Ack；KSU/APatch 未授权保持 awaitingAuth；授权后继续未取消的启动；旧会话仍健康时接入，避免重启核心 |
| stop | `{requestId, reason}` | Ack；reason 为 proxyStop/disable/switchToVpn/cancelAuth/acknowledgeFailure |
| cleanupResidue | `{requestId}` | Ack；停止并清理、关闭功能和自启 |
| getLogs | `{cursor:null或String, limit:1..500}`，默认 null/200 | `{sourcePath,entries:[{cursor,at,level,code,message}],nextCursor,eof}` |
| exportDiagnostics | `{requestId: UUID}` | `{path,sizeBytes,mimeType:"application/zip"}`；path 在 App 私有 cache 下，Flutter 保存/分享 |
| setAutostart | `{requestId: UUID,enabled: bool}` | Ack；序列化写入/删除唯一入口，文件事务后事件反映实际文件状态，不隐含启动 |

返回包装：

```json
{"ok":true,"data":{"requestId":"7fb480b6-08a9-4113-8505-912671462d51","intentRevision":1,"disposition":"accepted","snapshot":{"schemaVersion":1,"epoch":"session-uuid","seq":1,"intentRevision":1,"state":"awaitingAuth","rootManager":"kernelsu","authStatus":"notGranted","mode":"rootTun","rootTunEnabled":true,"autostartEnabled":false,"lastErrorCode":"ROOT_GRANT_REQUIRED_IN_MANAGER","lastErrorAt":1792713600000,"warnings":[],"authDeadlineAt":null,"startedAt":null,"updatedAt":1792713600000,"stale":false}},"error":null}
```

Ack 中 snapshot 为入列时的快照，可能仍是前一状态；不承诺 Ack 时已经授权/运行。同 requestId/有效参数重试返回原 Ack，改参数复用 ID 为 `INVALID_ARGUMENT`；保留最近 256 个请求。新生命周期 revision 取消旧启动/恢复意图。自启设置复用当前生命周期 revision，独立按最新 requestId 合并，避免改开关取消正在进行的启动；后来的 stop/start revision 会使旧设置任务失效。

```json
{"ok":false,"data":null,"error":{"code":"ROOT_NOT_FOUND","details":{"phase":"detectRoot"},"retryable":false}}
```

参数错误用 PlatformException `INVALID_ARGUMENT`；IO/通道错误用 `CORE_ERROR` + `{phase}`，不加入 PRD 用户错误枚举。前提检测返回 ok=true 的 degraded 快照，已知 degraded 前提下 start 返回业务失败。

八态及全部 27 个 PRD 错误常量见 RootTunProtocol.kt；rootManager 为 magisk/kernelsu/apatch/none/unknown，authStatus 为 unknown/notGranted/granted/denied/revoked。本轮 revoked 枚举预留，尚无可靠运行时撤权探测。

事件 listen 参数 `{schemaVersion:1,epoch:null或String,afterSeq:int}`。本轮使用完整 snapshot 事件（不发 delta）：

```json
{"schemaVersion":1,"epoch":"session-uuid","seq":2,"kind":"snapshot","requestId":null,"code":"CORE_RECOVERED","at":1792713600000,"snapshot":{"schemaVersion":1,"epoch":"session-uuid","seq":2,"intentRevision":1,"state":"running","rootManager":"kernelsu","authStatus":"granted","mode":"rootTun","rootTunEnabled":true,"autostartEnabled":false,"lastErrorCode":null,"lastErrorAt":null,"warnings":[],"authDeadlineAt":null,"startedAt":1792713600000,"updatedAt":1792713600000,"stale":false}}
```

先 getState，再 listen(epoch/seq)。补发最近 256 事件；域不符/无连续历史时发送新完整快照。detach 只退订，后台 Root 不停止。没有持久化状态时 stale=false；进程重建有缓存时先 stale=true，后台探测授权并调用 runtime.status()，核对后发布 stale=false。未授权到 awaitingAuth，前提不满足到 degraded；核对只接入已有运行实例，不自动接管。recheckRoot 也可再次核对；旧 revision 不得覆盖新命令。

KSU/APatch 不设授权倒计时；su 被隐藏时也参考已安装管理器包，给出去管理器授权的状态。Magisk 仅显式 start/requestAuth 执行可弹窗的 su，最多 30 秒。管理器隐藏/改包名及不同 fork 仍需真机验证。

## 诊断与手机联调

ZIP 包含设备/系统/包名（Android release、SDK、incremental、安全补丁、uname -a、PAGE_SIZE、ksud -V/固定路径版本、KernelSU properties、dmesg/logcat AVC 最后 200 行）、完整原生快照、App 状态记录、getenforce、双族 rule、全部路由表、link/addr、iptables-save/ip6tables-save、connectivity 的 VPN 行、core/validation/watchdog/状态迁移日志及启动前网络文本快照及 `logs/restore-diff.txt`。权限不足/命令不存在时保留失败和 stderr；无授权时不会为了导出主动弹 Magisk 授权框。凭据、订阅 URL 查询、代理 URI 做脱敏；不导出配置文件。disable 删除 runtime 前保留脱敏运行日志，并将完整 restore-diff.txt 复制到 App 创建的私有缓存文件，不受 su stdout 的 1MiB 上限截断；导出 ZIP 时统一脱敏。ZIP 缓存 24 小时后于下一次导出清理。无授权的诊断使用同一脚本以普通用户运行，权限/命令失败保留在证据中。exportDiagnostics 技术失败仅 CORE_ERROR + phase=exportDiagnostics；本轮未引入额外业务错误码。Flutter PR #23 仍需提供独立的 20 秒导出超时。

Flutter 同事需把上述方法接到界面，本分支不新增 Flutter 开关。真机测试者仅点按即可：选生效配置 → 启用 Root → KSU/APatch 管理器授权 → 返回重新检测 → 等 running → 浏览器确认出站 → 导出诊断。失败时直接导出；再点清理残留。无需 adb。

必须验证：小米 17 Pro Max（Android 17，KernelSU） SELinux 执行与 netlink、SO_MARK 全协议防回环、nc 命令和 su 后台保活、App/核心被杀后的恢复时限、UDP/TCP 53、自动/严格私人 DNS、IPv6 无业务泄露、Wi-Fi/移动切换、VPN 双向切换/Always-on lockdown、连续 20 次启停后规则差异。再补 Magisk/APatch 至少一种实测。

## 构建与本机检查

CI 需要递归拉取固定 core/Clash.Meta gitlink `8380d0e7462f061a964323e9bf3129a236fcc5d5`（SSH 凭据/HTTPS 重写由 DevOps 配置，本分支未改 .gitmodules），Go（本机 1.27.3）、项目指定 Flutter 3.47.x/Dart、JDK 17、Android SDK/NDK（Gradle 版本目录固定值），以及现有 Flutter/Rust 构建依赖。支持 Linux/macOS 的 sh 构建入口；不支持 Windows 本机的此脚本。

```sh
flutter pub get
flutter build apk --debug --target-platform android-arm64
# 可选双 ABI：
flutter build apk --debug --target-platform android-arm64,android-x64
# 现有 setup.dart android 同样经 Flutter/Gradle 触发该任务。
```

本分支已去掉 armeabi-v7a；默认和双目标只产生两个 64 位 ABI。Flutter 默认请求列表里的 android-arm 被 gomobile 过滤，单独 android-arm 目标会被 Root 核心任务拒绝。APK 应包含 `lib/<ABI>/libroot_mihomo.so`，安装后必须验证 nativeLibraryDir 中存在并可由 su 复制执行。

本轮返工验证（2026-10-23）：

- 使用已有缓存中固定 gitlink `8380d0e7462f061a964323e9bf3129a236fcc5d5` 的源码/依赖及 NDK r27c，重新执行修改后的 build-core.sh，arm64-v8a/x86_64 均成功。产物在 `out/root-jni-rework/`（不提交二进制）。readelf 检查所有 LOAD 段：arm64 为 0x10000，x86_64 为 0x4000，均满足 16KB 对齐；这不是仓库 NDK 28 的 APK 验证。
- Kotlin 2.2.20 在 JDK 21 上以 JVM 17 目标编译本轮 Root Kotlin、通道、ServiceState/MainActivity，并运行 `android/tests/app/root/` 的 17 项 JUnit，全部通过。使用真实 Android API 35/Flutter embedding/AndroidX/SnakeYAML JAR，但宿主/R/BuildConfig 使用已有 `out/check-stubs/` 临时桩；不等于仓库 AGP/Kotlin 版本下的模块编译。
- ShellCheck 0.11.0 对 runtime、service.d、诊断和构建脚本零报错；sh -n 通过。私有临时目录的命令模拟覆盖基线一致、计数/注释变化、真实残留差异/警告、采集失败保留 owned 以便重试，以及自启同 boot 幂等/开关关闭不启动。没有在宿主修改路由或启动 FlClash。
- 使用缓存 Gradle 9.1.0/AGP 9.0.0 隔离验证 app 的 ABI DSL：split 输出仅 arm64-v8a 和 x86_64；也检查单目标和非 split 配置。该隔离配置不能替代仓库 AGP 9.4.1 的正式 APK 构建。
- 已实际尝试 `./gradlew :app:compileDebugKotlin :app:assembleDebug -Ptarget-platform=android-arm64,android-x64`：仓库未带 gradlew，未执行。SDK 37、NDK 28.2.13676358、local.properties 和 core/Clash.Meta 子模块缺失；没有产出 APK，也未运行 app lint/安装/真机测试。
- 已尝试 `flutter pub get`、`flutter analyze --no-fatal-infos`、`flutter test test/core/protocol_contract_test.dart`：PATH 无 Flutter，使用已有 SDK 绝对路径后仍因其 cache 在只读文件系统、无法写 engine.stamp/engine.realm 而均未运行。本轮没有修改 Dart。
- 9 秒命令预算的实际超时探针在本机 9646ms 返回，小于 10 秒；这验证本机 su 等价子进程/双流收尾预算，设备上的 root 管理器与慢命令仍需手测。
- 结构自查范围：通道契约、状态核对、ServiceState 权限接缝、RootRuntime 文件操作及脚本边界；没有发现本轮引入且需额外重构的责任归属问题。ktlint 与 diff/comment-density 检查见工作区 `out/rework-*` 日志。

## 与完整 TDD/PRD 的差距和冲突

- 本轮按明确范围做原生最小实现。完整 TDD 的 Go root-agent/受认证 socket、分块 stage、Core JSON 数据桥、可靠配置 reload、无 App 的事件补发/epoch 由 root 持久化尚未实现。当前 root 生命周期由独立 sh 监督，Kotlin 编排授权/镜像状态；Flutter 原有 gomobile 统计/连接页不会自动转到独立核心。
- 网络保存为命名空间所有权标记 + 完整文本基线，不是 TDD 的结构化逐步 undo.jsonl；清理后重新采集双族 rule/所有表 route 和两种 iptables-save，去计数/注释后逐项 diff；差异写 logs/restore-diff.txt，并在 transitions.log 和快照 warnings 中记 CLEANUP_FAILED。差异本身不自动阻止已清理自有资源的停止；证据采集/比较工具失败则保留 owned 并继续清理重试。外部并发修改、网络切换情况下“全局与旧快照一致”需按 TDD Q1 继续解决。不得声称已证明全部规则还原。
- root 监督进程可独立于 App 恢复核心，但没有第二层独立 watchdog 监视监督进程本身；不覆盖 App/监督进程/核心同时被杀。恢复时会先清除并重装自有规则，存在短暂直连窗口；完整 TDD 要求恢复成功前保持接管，后续改为保留接管规则、只重启核心，并收敛到 agent/journal 方案；本轮仅登记，不改恢复策略。
- 10 秒启动/3 秒清理/30 秒恢复为本轮预算和轮询上限，su、资产复制、慢内核/多次规则命令的硬时限仍需设备压测，不能只凭代码宣称 P95 达标。
- 按本轮范围，**未完成的 P0：卸载检测、独立看门狗、授权撤销检测**，拆到后续 PR；本轮不实现评审第 9 项。service.d 入口与自启开关已实现，冷启动通知/撤权时 boot 的有效授权检查仍需后续闭环。Magisk 无通用无弹窗授权查询，本轮被动检测只保留已有授权信息，不能据此证明未撤权。
- IPv6 当前使用 OUTPUT filter；未实现 TDD 的额外 policy unreachable。代理出站 mark 的全覆盖、防漏和候选路由与 netd 冲突仍属 W1 真机门槛。私人 DNS 切换规则是逐条更新，尚不是完整原子网络事务。
- 磁贴操作已路由到 Root，但磁贴外观仍读上游 VPN RunState，Root 展示同步留后续；其他 VPN 并存不保证策略，按 R2 实测记录。
- PRD §5.1 的 failed 默认意味着直连，但又允许清理失败为 failed；按 TDD Q2，本轮清理未完成保持 stopping+CLEANUP_FAILED。PRD 关闭功能要求删除全部 R，与保留独立卸载监护的完整设计存在 Q2；本轮无卸载监护，disable 确认清理后删除 R。
- 控制通道使用 **TCP + token**，偏离 TDD §6.3 的受 SO_PEERCRED 认证的 Unix socket；不宣称已实现对端 UID 校验。exportDiagnostics 按评审统一为私有 path/sizeBytes/mimeType；删除 cleanup 别名，只保留 cleanupResidue。

## 评审逐项自查

| 清单编号 | 本轮结果与自查 |
| --- | --- |
| 1 | 完成：UUID 参数、私有 cache ZIP 三字段返回；移除 Activity/chooser/FileProvider/路径 XML；ZIP 实测和返回结构单测通过。 |
| 2 | 完成：单次 su 执行诊断 sh、分段标记、9 秒进程等待 + 最多 600ms 流收尾；有界超时探针通过。 |
| 3 | 完成：Android 17 所需系统/内核/KernelSU/AVC 字段、恢复 diff 打包；现场可用性待真机。 |
| 4 / B1 | 完成：新安装不 stale；持久化快照异步核对并发 stale=false；授权不足可等待/降级；新旧意图守卫和相关单测通过。 |
| 5 | 完成：复用 AppPlugin 通知权限，在 runtime.start 前请求 FGS；ForegroundServiceStartNotAllowedException 单独记录，不回滚 Root。后台/磁贴真机待测。 |
| 6 | 完成：proxyStop/cancelAuth/acknowledgeFailure 保留自启；仅 disable/switchToVpn（cleanupResidue 走 disable）关闭自启并删入口。 |
| 7 | 完成：safe-mode 返回 CORE_START_FAILED、retryable=false、reason=SAFE_MODE，不抛 CORE_ERROR；单测覆盖返回结构。 |
| 8 | 完成：删除 cleanup 平台通道别名。 |
| 9 | 按要求未做：独立看门狗、卸载与授权撤销检测留后续 PR。 |
| 10 | 完成限定范围：Kotlin setAutostart；固定、自有标记入口原子替换/精确删除；config 开关持久化；成功启动和状态核对读取真实入口文件状态；POSIX/幂等检查通过。 |
| 11 / B3 | 完成：双族/所有表/两种 save 归一化 diff、差异警告与快照 warnings、App cache 保留原文件并导出；模拟差异和失败重试通过。 |
| 12 | 完成文档登记：崩溃恢复有直连窗口，后续保留规则只重启核心；未改恢复逻辑。 |
| 13 | 完成：两 ABI 共用 -extldflags=-Wl,-z,max-page-size=16384，重编和 LOAD 对齐检查通过。 |
| 14 / B4 | 完成构建配置：Root 核心/gomobile/ABI 与 splits 均仅 64 位；双核心成功、隔离 split DSL 通过；两个完整 APK 尚未构建，CI 修改由 DevOps 负责。 |
| 15 | 完成：移除 manifest extractNativeLibs，仅保留 Gradle useLegacyPackaging。 |
| 16 | 完成：真机型号/Android 17、TCP+token 偏差、三项未完成 P0 已登记。 |

## 提交与交付

- 返工提交：`77f62e6`（feature/root-tun-native），已推送，并合入 feature/root-tun-integration（`9246550`）。
- 复审修正（N1 未授权且无启动意图时保持 disabled、N2 exportDiagnostics 校验 requestId、N3 本节）：紧随 `77f62e6` 的下一个提交，以 feature/root-tun-native 分支 HEAD 为准。
- 本机验证：Kotlin 编译、18 项 JVM 单测（宿主类使用临时桩）、shellcheck、ktlint 通过；完整 APK 由 CI 构建，未在本机产出。
- 未做：独立看门狗、卸载检测、授权撤销检测（B2 P0），留后续 PR；真机手测待进行。
