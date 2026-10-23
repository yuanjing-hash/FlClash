# Android Root TUN 原生最小实现

分支 `feature/root-tun-native`，2026-10-23。仅修改当前 worktree，未 push。
这是供 Flutter 接入和真机联调的原生实现；**本机未产出 APK，不能据此宣称真机可用或完整 P0 验收通过**。

## 文件与行为

- `app/src/main/kotlin/com/follow/clash/root/`：有界、可取消的 su 执行；root 管理器/授权检测；协议模型；配置及资源安装；状态/请求仲裁；DNS 自检；通知；诊断导出。
- `app/src/main/kotlin/com/follow/clash/plugins/RootTunPlugin.kt`、`MainActivity.kt`：注册 MethodChannel/EventChannel、分享面板。
- `ServiceState.kt`：Root 入口仍由此持有；启动 Root 先取消并停止旧服务；Root 模式阻止原 VPN start；切回 VPN 必须先 `stop(switchToVpn)`。磁贴/快捷方式的启动/停止转交 Root 后端。
- `app/src/main/assets/root-tun/runtime.sh`：独立 su 后台监督进程。唯一写网络规则和启动核心的组件；PID 同时核对 startTicks 和 boot ID。崩溃后恢复，5 分钟第 3 次崩溃熔断；恢复失败清理规则；清理失败保持 stopping 并重试。
- `root-tun/build.gradle.kts`、`root-tun/build-core.sh`：Gradle 自动构建独立 mihomo，按 ABI 作为 `libroot_mihomo.so` 加入 generated jniLibs；保留可执行 ELF，不调用 System.loadLibrary。
- `settings.gradle.kts`、`app/build.gradle.kts`、manifest、XML/中英文资源：所有构建的 applicationId 为 `com.follow.clash.root`；namespace/两个 packageName 常量不改。64 位 ABI、legacy packaging/extractNativeLibs、非 VPN 前台服务及仅暴露诊断缓存子目录的 FileProvider。SAFE_MODE 编译开关拒绝 Root 变更命令。
- `android/tests/app/root/`：su 转义/双流/超时/输出界限、状态枚举/空字段、DNS 响应校验、日志脱敏。

配置来源为 App `filesDir/config.yaml`，不是示例空配置。保留节点/规则/DNS，迁移本地 provider/geo 文件；路径限于 App filesDir，单文件 256 MiB、总额 512 MiB。select 组按 SharedState selected-map 排序，优先保留当前选中项。测试配置成功才引流。

强制 gVisor TUN、auto-route、auto-detect-interface、strict-route、any:53；不使用 VpnService fd。独占表 2022、pref 8990–9011、`flcrtun0`、FCR_OUTPUT；启动前整段查空。使用 routing-mark `0x40000000` + goto 越过接管区，未沿用 spike 的 UID 0 全体豁免。控制器只绑定随机的 127.0.0.1 端口并使用每次生成的凭据；关闭其他入站和外部 UI。IPv6 业务在 OUTPUT 阻断，仅放行 loopback 和 NDP。私人 DNS 自动模式拒绝非核心 853，严格模式保留服务器、通过 warnings 提示。

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
| cleanup | `{requestId}` | cleanupResidue 的额外别名（本轮需求） |
| getLogs | `{cursor:null或String, limit:1..500}`，默认 null/200 | `{sourcePath,entries:[{cursor,at,level,code,message}],nextCursor,eof}` |
| exportDiagnostics | `{}` | `{uri:"content://…",mimeType:"application/zip",shared:true}`，并打开系统分享（本轮扩展，TDD 未定义） |
| setAutostart | — | MethodNotImplemented，Flutter 应隐藏；service.d 留待后续 |

返回包装：

```json
{"ok":true,"data":{"requestId":"7fb480b6-08a9-4113-8505-912671462d51","intentRevision":1,"disposition":"accepted","snapshot":{"schemaVersion":1,"epoch":"session-uuid","seq":1,"intentRevision":1,"state":"awaitingAuth","rootManager":"kernelsu","authStatus":"notGranted","mode":"rootTun","rootTunEnabled":true,"autostartEnabled":false,"lastErrorCode":"ROOT_GRANT_REQUIRED_IN_MANAGER","lastErrorAt":1792713600000,"warnings":[],"authDeadlineAt":null,"startedAt":null,"updatedAt":1792713600000,"stale":false}},"error":null}
```

Ack 中 snapshot 为入列时的快照，可能仍是前一状态；不承诺 Ack 时已经授权/运行。同 requestId/有效参数重试返回原 Ack，改参数复用 ID 为 `INVALID_ARGUMENT`；保留最近 256 个请求。新 revision 取消旧启动/恢复意图。

```json
{"ok":false,"data":null,"error":{"code":"ROOT_NOT_FOUND","details":{"phase":"detectRoot"},"retryable":false}}
```

参数错误用 PlatformException `INVALID_ARGUMENT`；IO/通道错误用 `CORE_ERROR` + `{phase}`，不加入 PRD 用户错误枚举。前提检测返回 ok=true 的 degraded 快照，已知 degraded 前提下 start 返回业务失败。

八态及全部 27 个 PRD 错误常量见 RootTunProtocol.kt；rootManager 为 magisk/kernelsu/apatch/none/unknown，authStatus 为 unknown/notGranted/granted/denied/revoked。本轮 revoked 枚举预留，尚无可靠运行时撤权探测。

事件 listen 参数 `{schemaVersion:1,epoch:null或String,afterSeq:int}`。本轮使用完整 snapshot 事件（不发 delta）：

```json
{"schemaVersion":1,"epoch":"session-uuid","seq":2,"kind":"snapshot","requestId":null,"code":"CORE_RECOVERED","at":1792713600000,"snapshot":{"schemaVersion":1,"epoch":"session-uuid","seq":2,"intentRevision":1,"state":"running","rootManager":"kernelsu","authStatus":"granted","mode":"rootTun","rootTunEnabled":true,"autostartEnabled":false,"lastErrorCode":null,"lastErrorAt":null,"warnings":[],"authDeadlineAt":null,"startedAt":1792713600000,"updatedAt":1792713600000,"stale":false}}
```

先 getState，再 listen(epoch/seq)。补发最近 256 事件；域不符/无连续历史时发送新完整快照。detach 只退订，后台 Root 不停止。进程重建后的缓存带 stale=true，应 recheckRoot 核对；不能凭缓存宣称当前接管有效。

KSU/APatch 不设授权倒计时；su 被隐藏时也参考已安装管理器包，给出去管理器授权的状态。Magisk 仅显式 start/requestAuth 执行可弹窗的 su，最多 30 秒。管理器隐藏/改包名及不同 fork 仍需真机验证。

## 诊断与手机联调

ZIP 包含设备/系统/包名、完整原生快照、App 状态记录、getenforce、双族 rule、全部路由表、link/addr、iptables-save/ip6tables-save、connectivity 的 VPN 行、core/validation/watchdog/状态迁移日志及启动前网络文本快照。权限不足/命令不存在时保留失败和 stderr；无授权时不会为了导出主动弹 Magisk 授权框。凭据、订阅 URL 查询、代理 URI 做脱敏；不导出配置文件。disable 删除 runtime 前保留一份脱敏日志到 App 缓存。分享缓存 24 小时后于下一次导出清理。

Flutter 同事需把上述方法接到界面，本分支不新增 Flutter 开关。真机测试者仅点按即可：选生效配置 → 启用 Root → KSU/APatch 管理器授权 → 返回重新检测 → 等 running → 浏览器确认出站 → 导出诊断。失败时直接导出；再点清理残留。无需 adb。

必须验证：小米 Android 16/KernelSU SELinux 执行与 netlink、SO_MARK 全协议防回环、nc 命令和 su 后台保活、App/核心被杀后的恢复时限、UDP/TCP 53、自动/严格私人 DNS、IPv6 无业务泄露、Wi-Fi/移动切换、VPN 双向切换/Always-on lockdown、连续 20 次启停后规则差异。再补 Magisk/APatch 至少一种实测。

## 构建与本机检查

CI 需要递归拉取固定 core/Clash.Meta gitlink `8380d0e7462f061a964323e9bf3129a236fcc5d5`（SSH 凭据/HTTPS 重写由 DevOps 配置，本分支未改 .gitmodules），Go（本机 1.27.3）、项目指定 Flutter 3.47.x/Dart、JDK 17、Android SDK/NDK（Gradle 版本目录固定值），以及现有 Flutter/Rust 构建依赖。支持 Linux/macOS 的 sh 构建入口；不支持 Windows 本机的此脚本。

```sh
flutter pub get
flutter build apk --debug --target-platform android-arm64
# 可选双 ABI：
flutter build apk --debug --target-platform android-arm64,android-x64
# 现有 setup.dart android 同样经 Flutter/Gradle 触发该任务。
```

不接受仅 android-arm 目标。APK 应包含 `lib/<ABI>/libroot_mihomo.so`，安装后必须验证 nativeLibraryDir 中存在并可由 su 复制执行。

本机结果：

- 使用 spike 缓存中**相同 SHA** 的源码和依赖，通过新 build-core.sh 构建 arm64 与 x86_64；ELF64 PIE，解释器 `/system/bin/linker64`；x86_64 仅依赖 Android liblog/libdl/libc。产物在 `out/root-jni/`，未提交大二进制。
- 新 root-tun Android library 模块通过隔离的 Gradle 9.1.0 / AGP 9.0.0 配置检查；此检查不是仓库 AGP 9.4.1 的完整 APK 构建。
- Kotlin 2.2.20/JVM 17 编译所有新增原生 Kotlin、通道和修改的 ServiceState/MainActivity，通过；使用真实 Android API 35（Robolectric android-all）、Flutter embedding 3.35.4、AndroidX、SnakeYAML 等 JAR。**既有宿主/生成 R/BuildConfig 使用 out/ 中的临时桩，不能替代本项目 Gradle/APK 编译**。
- JUnit 7 项通过；ktlint 1.7.1、sh -n、ShellCheck 0.11.0、comment-density 和 diff 检查通过。临时命令模拟确认：无所有权时不修改网络，已有冲突/读取被拒不能误报清理成功，已认领清理仅 flush 表 2022。
- 已尝试 flutter pub get / flutter analyze --no-fatal-infos / 覆盖的 flutter test；本机无 Flutter 命令，均未运行。本机无 Android SDK，仓库也未带 Gradle wrapper；另下载 Gradle 仅验证上述隔离配置，未运行模块 Kotlin/资源 Gradle 编译或产出/安装 APK；需要 CI 完成正式构建。

## 与完整 TDD/PRD 的差距和冲突

- 本轮按明确范围做原生最小实现。完整 TDD 的 Go root-agent/受认证 socket、分块 stage、Core JSON 数据桥、可靠配置 reload、无 App 的事件补发/epoch 由 root 持久化尚未实现。当前 root 生命周期由独立 sh 监督，Kotlin 编排授权/镜像状态；Flutter 原有 gomobile 统计/连接页不会自动转到独立核心。
- 网络保存为命名空间所有权标记 + 完整文本基线，不是 TDD 的结构化逐步 undo.jsonl；清理确认自有资源消失，不把所有网络快照差异自动判失败。外部并发修改、网络切换情况下“全局与旧快照一致”需按 TDD Q1 继续解决。不得声称已证明全部规则还原。
- root 监督进程可独立于 App 恢复核心，但没有第二层独立 watchdog 监视监督进程本身；不覆盖 App/监督进程/核心同时被杀。恢复时会先清除并重装自有规则，存在短暂直连窗口；完整 TDD 要求恢复成功前保持接管，后续须收敛到 agent/journal 方案。
- 10 秒启动/3 秒清理/30 秒恢复为本轮预算和轮询上限，su、资产复制、慢内核/多次规则命令的硬时限仍需设备压测，不能只凭代码宣称 P95 达标。
- 运行时撤权、卸载监护、开机 service.d、自启开关及冷启动通知未完成。Magisk 无通用无弹窗授权查询，本轮被动检测只保留已有授权信息，不能据此证明未撤权。
- IPv6 当前使用 OUTPUT filter；未实现 TDD 的额外 policy unreachable。代理出站 mark 的全覆盖、防漏和候选路由与 netd 冲突仍属 W1 真机门槛。私人 DNS 切换规则是逐条更新，尚不是完整原子网络事务。
- 磁贴操作已路由到 Root，但磁贴外观仍读上游 VPN RunState，Root 展示同步留后续；其他 VPN 并存不保证策略，按 R2 实测记录。
- PRD §5.1 的 failed 默认意味着直连，但又允许清理失败为 failed；按 TDD Q2，本轮清理未完成保持 stopping+CLEANUP_FAILED。PRD 关闭功能要求删除全部 R，与保留独立卸载监护的完整设计存在 Q2；本轮无卸载监护，disable 确认清理后删除 R。
- TDD 接口不包含 exportDiagnostics/cleanup，按本轮明确需求增加导出与别名；正式清理名仍提供 cleanupResidue。service.d 明确留 TODO，不用未实现开关假装支持。

## 提交限制

实际 worktree 的 Git 元数据目录只读，git add 创建 index.lock 失败；原分支没有新增提交。按需求导出 out/root-tun-patches/ 下按功能划分的 Conventional Commit patch 系列；临时导出仓库仅用于生成/校验 patch，不等于已提交到 feature/root-tun-native。没有 push。
