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

## exportDiagnostics 契约

`exportDiagnostics({requestId: UUID})`，Dart 单独等待上限 20 秒，沿用幂等 ID 和 Result：

```json
{"ok":true,"data":{"path":"/data/user/0/<applicationId>/cache/root-tun-diagnostics.zip","sizeBytes":12345,"mimeType":"application/zip"},"error":null}
```

`path` 是原生已经打包完成、Flutter 可读的 App 私有目录文件的绝对路径，`sizeBytes` 是非负整数、与文件实际长度一致，`mimeType` 为 `application/zip`（Flutter 在缺省时也使用该值）。不得返回 `/data/adb` 下的 root 文件；日志页同样只显示 `sourcePath`，不直接读取它。原生应在该等待上限内返回已经生成的诊断包；大文件打包需要预生成或另行扩展异步契约。

失败使用 `{ok:false,data:null,error:{code,details,retryable}}`，技术失败可以 `PlatformException('CORE_ERROR', ..., {phase:'exportDiagnostics'})`。未实现使用标准 `notImplemented`；App 明确提示「原生端尚未支持导出诊断」。保存/分享由 Flutter 负责，原生不弹分享面板。Flutter 验证路径归属和长度，再将 `mimeType` 传给现有文件保存器调起系统保存位置选择。取消保存不删除诊断包；文件轮换由原生负责。

## 验证与手测

测试覆盖模型必填字段/枚举、Result、事件补丁与断号/新 epoch、订阅顺序、迟到 Ack、超时、通道缺失、授权界面、失败确认、诊断降级和日志分页。使用 Flutter 3.47.6 / Dart 3.13.5 生成 Freezed、JSON、Riverpod 和 intl 输出。

真机仍需与原生联调：小米 17 Pro Max（Android 17，KernelSU）的授权返回和恢复、管理器包名变种、Root/VPN 互斥、开关关闭时的自启清理、诊断文件保存。首版 Flutter 不包含原生实现，不能仅凭 UI/Ack 判断流量已接管。
