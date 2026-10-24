# Root TUN Flutter 首版

Android 的「网络」设置在 VPN 区附近显示 Root TUN 开关、开机自启、模式、8 态、管理器、授权和最近错误。首页显示相同快照；其他平台不创建 Root TUN 控件或连接。Kotlin/Go、CoreLib、applicationId 和 `packageName` 未修改。错误中文来自 PRD v1 附录 B；英文已补齐，其他语言暂用英文。

## 原生对接

协议以技术负责人 TDD §6.1 为准，沿用 `lib/common/constant.dart` 的 `packageName`：

- MethodChannel：`$packageName/root_tun`。
- EventChannel：`$packageName/root_tun/events`。
- getter：`getState({})`、`detectRoot({})`、`getLogs({cursor, limit})`，Dart 等待上限 3 秒。
- 命令：`recheckRoot`、`requestAuth`、`start`、`stop({requestId, reason})`、`setAutostart({requestId, enabled})`、`cleanupResidue`，Dart 等待上限 2 秒。未标参数的命令只传 `{requestId}`。UUID 由 Flutter 生成，调用层也可指定相同 ID 重试。
- `stop.reason`：`proxyStop / disable / switchToVpn / cancelAuth / acknowledgeFailure`。
- 所有返回都是 StandardMethodCodec 的 Map：`{ok, data, error}`，不能返回 JSON 字符串或 bool；命令 data 为 Ack。Ack 不代表运行成功。
- 先 getState，再订阅 `{schemaVersion:1, epoch, afterSeq}`。旧序号丢弃，delta 保留未提供字段并应用显式 null；断号或不匹配的 baseSeq 重新取快照并订阅。完整事件可重置新 epoch。
- 缺失实现、`notImplemented`、`CORE_ERROR` 和协议异常都保留可诊断信息，已有状态标记 stale，通信错误不写业务 lastErrorCode，不伪造 disabled。
- stale 时仍可重新检测和停止（所有 `stop.reason`），启动、自启设置和残留清理继续禁用。`setAutostart` 返回 `notImplemented` 或 `MissingPluginException` 后隐藏开机自启开关。
- 超时不会取消原生命令。Flutter 控制层随后 getState；错误详情保留 requestId。取消授权只发 `stop(cancelAuth)`。卸载/页面销毁只退订事件，不停止 root 核心。
- KernelSU/APatch：原生应返回 `awaitingAuth / notGranted / authDeadlineAt:null`，授权由管理器完成。Flutter 提供管理器入口、重新检测和取消，不自行计时。Magisk 的倒计时仅展示 `authDeadlineAt`，到 0 仍等待原生结果。
- 原生负责 Root/VPN 互斥、授权/启动/恢复期限、自启落盘和状态收敛；既有核心数据桥不变。

## 弹窗去重

设置页的失败、`CLEANUP_FAILED`、`ROOT_PERMISSION_REVOKED`、`MODE_SWITCH_FAILED` 和 KernelSU/APatch 待授权提示，由 `RootTunController.markPromptShown` 按 **`Snapshot.epoch + code`** 预占并去重。TDD §6.1 将 `epoch` 定义为重装 runtime/重启时更新的会话域；Snapshot 没有独立的 `sessionId`。`seq`、`intentRevision`、状态和错误时间会随同一会话的事件变化，`startedAt` 在授权阶段可能为空、恢复后也可能变化，因此不作为去重键。

沿用 `Preferences`/SharedPreferences 的 `rootTunPromptHistory` 字符串列表，首项是当前 epoch，其余是已提示的协议 code；最多保留当前会话的 27 个已知码，新 epoch 覆盖旧记录。控制层先加载记录再发布快照，弹窗前先在内存预占并等待串行落盘，离开/重进页面和 Flutter 进程重建后仍生效。异步写入期间已换会话或显式重新启动的旧提示会失效。

仅用户显式调用 controller `start()`（包括打开设置页开关）清空已提示码，并在发出原生启动命令前保存；后续命令共用这次写入屏障，保证快速 start/stop 的发送顺序，但不等待前一命令的 Ack。被 stale 状态拦截的启动不清空。`refresh`、检测/重新检测、自动恢复、看门狗重启和事件刷新在同一 epoch 内保留记录。K1 的 `LAST_SESSION_ABNORMAL_EXIT` 横幅和 K7 UI 维持原行为。

## exportDiagnostics 契约

`exportDiagnostics({requestId: UUID})`，Dart 单独等待上限 20 秒，沿用幂等 ID 和 Result：

```json
{"ok":true,"data":{"path":"/data/user/0/<applicationId>/cache/root-tun-diagnostics.zip","sizeBytes":12345,"mimeType":"application/zip"},"error":null}
```

`path` 是原生已经打包完成、Flutter 可读的 App 私有目录文件的绝对路径，`sizeBytes` 是非负整数、与文件实际长度一致，`mimeType` 为 `application/zip`（Flutter 在缺省时也使用该值）。不得返回 `/data/adb` 下的 root 文件；日志页同样只显示 `sourcePath`，不直接读取它。原生应在该等待上限内返回已经生成的诊断包；大文件打包需要预生成或另行扩展异步契约。

失败使用 `{ok:false,data:null,error:{code,details,retryable}}`，技术失败可以 `PlatformException('CORE_ERROR', ..., {phase:'exportDiagnostics'})`。未实现使用标准 `notImplemented`；App 明确提示「原生端尚未支持导出诊断」。保存/分享由 Flutter 负责，原生不弹分享面板。

`lib/common/root_tun_diagnostics.dart` 的 `RootTunDiagnosticsExporter` 先解析文件与 App 私有目录的符号链接，使用 `isWithin` 验证路径归属，再核对实际长度与 `sizeBytes`；校验失败不打开保存/分享面板。

- Android 使用 Flutter Community 的 `share_plus` 13.3.1，以 `XFile(path, mimeType: ...)` 调起系统分享面板，用户选择接收应用（可用的保存目标取决于设备上安装的应用）。Dart 平台通道只传路径与 MIME 类型；插件在后台通过 Kotlin `File.copyTo` 的缓冲流复制到自己的分享缓存，再通过 FileProvider 授予接收方 URI 访问权限，Dart 和插件都不整包读入内存。此方式需要额外一份磁盘缓存。分享结果 `success` 表示已选择接收应用，不能保证接收应用已经完成保存；取消或结果不可用不提示成功，也不删除源诊断包。
- Root TUN 只在 Android 上提供，导出器在其他平台直接抛出 `UnsupportedError`，不读取文件。

新增依赖的原因：现有 `picker.saveFile` 和 `saveFileWithPath` 都要求整包 bytes；file_picker 12.3.0 的 `saveFile` 强制接收 `Uint8List`，Android 实现通过 MethodChannel 将 bytes 交给原生写入 SAF，未提供源路径保存或 URI 分块写入接口。故 Android 改用主流的 `share_plus`，无需修改 Kotlin/Go、packageName 或 applicationId。源诊断包的文件轮换仍由 Root TUN 原生端负责。

## 验证与手测

测试覆盖模型必填字段/枚举、Result、事件补丁与断号/新 epoch、订阅顺序、迟到 Ack、超时、通道缺失、授权界面、失败确认、诊断降级和日志分页。`test/common/root_tun_diagnostics_test.dart` 另覆盖导出路径/符号链接校验、长度不符、取消/错误、Android 路径与 MIME 通道参数、桌面流式复制，以 fake 禁止整包读取。使用 Flutter 3.47.6 / Dart 3.13.5 生成 Freezed、JSON、Riverpod 和 intl 输出。

真机仍需与原生联调：小米 17 Pro Max（Android 17，KernelSU）的授权返回和恢复、管理器包名变种、Root/VPN 互斥、开关关闭时的自启清理、诊断文件保存。首版 Flutter 不包含原生实现，不能仅凭 UI/Ack 判断流量已接管。
