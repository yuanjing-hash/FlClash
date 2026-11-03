# Android Root TUN：方案 B 的 P0 后续实现

工作分支：`feature/root-tun-p0`；基线：`feature/root-tun-native@8f38fc6`（PR #22 二次复审通过）。
本轮基于 `e37003d` 返工 PR #31，完成 B1–B3、M1–M4 的代码与宿主模拟，并处理或登记非阻塞建议。
**尚未完成真机验收；不能据此关闭四个 P0、合入 main 或宣称方案 B 已通过验收。**

唯一运行目录为 `/data/adb/flclash-root/`（R），唯一开机入口为 `/data/adb/service.d/flclash-root.sh`。
不改 Dart、`com.follow.clash` 包名/通道常量、构建 ABI 和已有 VPN 后端；未启动宿主 FlClash，未修改宿主网络，未 push。

## #25：独立 watchdog

实现位于 `app/src/main/assets/root-tun/runtime.sh`。

- supervisor 与 watchdog 分别通过 `nohup + setsid + 二次 fork` 启动，关闭 stdin/stdout/stderr 的 su 管道继承。
  PID、锁、代际和心跳均放在 R/run；PID 同时核对 `/proc/<pid>/stat` startTicks、boot_id，并排除 zombie。
- 两个心跳文件采用 TDD §6.3 的 JSON 字段：schemaVersion、pid、startTicks、bootId、bootMs、sessionId；
  当前 sessionId 使用监督代际，期限使用 boot 单调秒。watchdog 每秒循环，supervisor 重建失联 watchdog。
- `owner.lock` 保持唯一网络/状态写者；watchdog 仅在接管时终止已核验的旧 supervisor、递增 generation 后写状态。
  心跳允许 5 秒间隔；core 的 PID、API、TUN 和网络规则健康时交给新 supervisor；失联后的前 24 秒
  保留拦截并重试健康检查，预算耗尽才清理并进入 `failed(CORE_RECOVERY_FAILED)`。adopt 共用该截止时间。
- core 崩溃恢复保留接管及 DNS/IPv6 防漏规则，只重启 core；IPv4 FCR_OUTPUT 增加非 TUN 出口拒绝规则，
  防止 TUN 消失后回落到物理网络。恢复失败才 cleanup/fail-open。恢复起止单调时间写入 supervisor.log。
- 5 分钟崩溃窗口持久化在 R/run，跨 supervisor 接管保留；第 3 次进入 CORE_CRASH_LOOP。
  旧 boot 的 PID、网络所有权和崩溃记录不被当成当前 boot 的资源。
- watchdog 的退出 trap 仅释放自己的 PID、探测子进程和锁，不拆正在运行的规则。proxyStop 结束 supervisor/core
  和已记录的 boot 任务，保留仅监护的 watchdog；显式 cleanup/disable 删除 R 前结束 watchdog。
  失败态保留卸载监护；撤权并清理成功后最多监护 10 分钟。watchdog.log 按当前/上一份 2×1MiB 轮换。

模拟覆盖：单实例、慢 pm 不阻塞心跳、watchdog TERM/KILL 后服务继续、supervisor 接管不重启 core、
core 恢复不拆规则、supervisor/core 同时死亡后清理及空 restore-diff、正常 stop、旧版本监督进程接管、跨接管熔断。

真机必验：小米 17 Pro Max（Android 17，KernelSU）上结束 su 会话/强停 App 后仍存活；
watchdog 重建 ≤3s，恢复或 fail-open ≤30s，清理 ≤3s；抓包证明恢复期间业务/DNS 不直连。
setsid 不等于已经证明 KernelSU 的会话/cgroup 行为，脚本模拟也不能证明真实 netlink/iptables 时延。

## #26：精确卸载检测

`runtime.sh` 的 package 探测在独立短任务中执行，watchdog 每 10 秒触发；每次都有短超时，结果带任务 ID。
固定查询 `pm path com.follow.clash.root` 和该包的 `pm list packages`，同时检查 `/data/data/com.follow.clash.root`。
只接受完整行 `package:com.follow.clash.root`，不依赖 APK 安装路径的命名，也不匹配官方版或同前缀包。

- 连续两次包、目录均不存在才清理。超时、包服务错误、格式异常或互相矛盾的结果都是 unknown，并清零连续计数。
- AOSP 的 `pm path` 在包不存在时正常返回 1。因此仅当其输出为空，且第二次独立的精确 list 查询成功确认不存在时，
  才视为 absence；不是把任意非零退出当成卸载。Binder/命令失败和超时均不计数。
- cleanup 完成后，只删除带已知 v1/v2 marker 的那一个 service.d 文件，再删除 R、自退出。
  删除 R 前用 `log -t FlClashRoot` 记录判定与清理结果；清理失败保留 R 并重试。
- boot 也执行相同的连续确认，覆盖卸载期间关机；不依赖 App 回调。

TDD §5/W5 的实现口径：`pm uninstall -k` 保留精确数据目录时不判定卸载；升级时只要目录仍在，也不删除 R。
授权记录另行明确撤销仍会触发 #29 的网络清理。此口径记录于本 REPORT，外部 TDD 尚需技术负责人同步回填。

模拟覆盖：完整包名/相似包、pm 失败/超时/Binder 错误、Android exit 1、保留数据、连续计数重置、
自有入口删除/其他入口保留、logcat 留痕。真机须分别验证系统卸载、pm uninstall、覆盖升级、卸载官方版，
证明 ≤60s 清理、重启无残留；保留数据卸载按上述 W5 口径验收。

## #28：service.d 与自启完善

- `service.d.sh` 是 v2 薄入口，只定位 R 并脱离前台调用 runtime。runtime 缺失时只删除已知 marker 的自有入口。
  当前兼容 v1/v2；不认识的 marker、符号链接和其他文件不覆盖、不删除。
- runtime 等待 boot_completed 最多 120s，等待用户 0 解锁最多 300s；每 2 秒重查，
  `am get-started-user-state 0` 有 1 秒超时，匹配 RUNNING_UNLOCKED，未成立则回退 `getprop sys.user.0.ce_available=true`。
  解锁后最多 50s 等包/网络依赖，另留 10s 启动。配置异常或依赖超时保持直连并记录 AUTOSTART_FAILED。
- 原子 `config/settings.json` 为规范化的 schemaVersion/rootTunEnabled/autostartEnabled；兼容既有两个开关文件。
  仅双开关都为 true 才提交启动。单个 R/run/boot-id 覆盖写入，不继续累积 boot-* 目录；
  升级时只 rmdir 精确 UUID 命名的旧空目录。boot.log 按 2×1MiB 轮换。
- control/owner 锁和同 boot 标记使重复入口/App 启动收敛到一组进程。proxyStop 保留自启设置，
  当前 boot 的延迟启动不能覆盖 stop；新 boot 可再次启动。disable/switchToVpn 关闭自启并删除运行目录。
- Kotlin setAutostart 保持异步 Ack，原子写临时入口、chmod 0700/chown 0:0、mv，并同步配置和实际开关状态。
  开启前要求功能已开启且获权；关闭仅删除已知自有入口。文件事务 su 等待预算为 2.3s，保留流收尾预算。
- 接入健康运行实例时原子更新脚本和已知旧入口；旧 supervisor 通过接管切换，不重建 core/TUN，补齐恢复防漏规则。

模拟覆盖：重复 boot、proxyStop 后新 boot、自启关闭、损坏配置、boot/依赖超时、旧空目录清理、
日志轮换、runtime 缺失、未知 marker/软链接保护及旧监督进程接管。
真机须验证：不打开 App，解锁后 ≤60s running；开关各 10 次；App/boot 并发、升级连接中断 ≤3s；
0700/root:root、Magisk/APatch 的 service.d 时序、300s 后才解锁的明确失败行为。

## #29：授权撤销检测

`authorization.sh` 只读管理器记录；不把 daemon 自身 UID=0 当成 App 授权证明。

| 路径 | 当前实现 | 验证边界 |
| --- | --- | --- |
| App 存活 | Magisk 禁止后台 su 探测及状态轮询，读 root 侧签名回传；其他管理器仅在 runtime 可能存在且处于活动/清理态时探测，每 5s 最多一次，连续两次明确拒绝才发 revoked | proxyStop 后不再 su 探测；超时、可执行文件不可用和无法分类的失败为 unknown；实际管理器拒绝输出待 W3 |
| KernelSU | 解析 `/data/adb/ksu/.allowlist`：magic、v2/v3 的 776 字节及 v4 的 784 字节记录，精确 package/UID/allow_su | 依据上游 UAPI；格式/版本/长度异常为 unknown；**未在目标手机核实，W3 未关闭** |
| Magisk | `magisk --sqlite` 精确查 app UID 的 policy/until；识别拒绝、删除记录和过期 | 兼容命令与固定安装路径；执行失败、超时、未知输出不计拒绝；待实机 |
| APatch | 读取 `/data/adb/ap/package_config`，校验 CSV 结构并精确 package/UID/allow | 已知无引号格式；未知格式不计拒绝；待实机 |

watchdog 的慢探测子任务每约 2s 调度，已有任务未结束时不重入，不阻塞每秒心跳。
管理器连续两次明确拒绝，或 App 已确认撤权，才持 control/owner 锁停止旧 supervisor、清理网络、关闭自启，
随后写 `failed(ROOT_PERMISSION_REVOKED)` 与 authStatus=revoked。清理失败保持 stopping+CLEANUP_FAILED，
持久化撤权原因继续重试，不提前宣称已直连。boot 在写规则前先验证管理器有效授权；unknown 放弃启动，
明确撤销则 cleanup、记录 AUTOSTART_ROOT_REVOKED，并尝试通过 `cmd notification post` 发系统通知。

App 与 root 的撤权交接使用新的有限本机通道：App 在 127.0.0.1 监听，root 发送随机 nonce，
双方用私有随机 token 对 nonce/固定状态计算 SHA-256 签名；不在网络上传 token，不接受 shell/路径参数。
App 连续拒绝后的 verdict 交给 watchdog；root 清理完成后回送签名确认，App 才发布 failed/revoked。
root 探测同时将 state/status、auth-status、private-dns、自启入口及恢复差异状态签名回传；Magisk 的后台
重连和状态监视均消费该结果，不启动 su。无回传时保留待核状态，显式 start 可授权并安装新版脚本。
端口/token 在 App 私有目录持久化并配置到 R；显式重试时轮换 token，拒绝旧会话的清理确认。
App 重建可接收此前的清理结果；App 强停时靠管理器记录独立清理。
撤权后的 watchdog 保留结果交接与卸载监护最多 10 分钟，清理失败不启动该退出预算。显式 cleanup/disable
可提前结束。预算到期保留磁盘诊断与失败状态，后续卸载可能留下 R；这是尊重撤权后不继续常驻 root 的取舍。
业务错误仍仅使用附录 B 的 27 个码。

模拟覆盖：KSU grant/deny/未知 ABI、Magisk grant/deny/过期/超时/失败、APatch 精确记录/损坏格式、
两次拒绝及 unknown 重置、清理后才报失败、清理失败重试保留原因、自启关闭与未知入口保留；
JVM 覆盖 App 超时不算撤权、连续拒绝、签名校验、伪造确认拒绝、凭据重开和重试时清除旧确认。

真机必验：W3 三家授权记录读取与更新延迟，App 前台撤权 ≤15s，强停后撤权，boot 撤权不写规则，
authStatus/错误码与通知可见性，重新授权后恢复；Android 17 本机端口访问、App 重建/端口重连、
通知权限与后台限制。**这些没有实机证据，本轮不能声称 #29 的 AC 已全部通过。**

## 复审非阻塞建议

- N2：Plugin 在进入 exportDiagnostics 前调用 requireRequestId，单独捕获参数异常；非 UUID 也返回
  INVALID_ARGUMENT（phase=exportDiagnostics），打包/执行失败继续用 CORE_ERROR。
- Controller recheck：抽出 Controller 自身使用的 recheckedAuth 决策，新增 disabled + notGranted 无启动意图的单测，
  并覆盖待授权/取消意图。撤权后的明确 recheck 重新进入授权启动流程（Magisk 可重新弹窗），已确认/关闭的失败不自动启动。这是 Controller 决策测试，不是 Android Context/Service 端到端测试。
- normalize：去计数、注释、expires/age/used，以及 RA/kernel 协议元数据；保留真实路由、下一跳、metric 和规则变化。
  成功 running 或成功 cleanup 清除 restore-diff 告警标记；真实差异仍保留证据并提示 CLEANUP_FAILED。
- 诊断采集补充 heartbeat/generation/boot-id/owned.boot/auth-status 以及轮换后的 supervisor/watchdog/boot 日志；
  不导出授权通道 token、配置密钥或管理器完整授权列表。

## PR #31 返工对照（已提交：2fe74a5、6fb6246、e9f1cce，合并于 b9fbd4a）

已完整阅读 `out/p0-inputs/review-31.md`，包含 9 条行内评论与 12 项真机清单。

| 项目 | 处理 | 对应验证 |
| --- | --- | --- |
| B1 | 删除不存在的 cmd user 子命令，am 判 RUNNING_UNLOCKED，未成立时回退 CE 属性；等待上限仍为 300s | boot-test 不替换 user_unlocked；am 命令桩覆盖直接解锁、锁定后解锁、am 不可用仅属性成功、两者失败超时 AUTOSTART_FAILED |
| B2 | Magisk 不做 App su 探测，root 的 authorization.sh 查管理器并通过状态文件/签名通道回传；后台 status 和 App 重连同样不调用 su。其他管理器增加 runtime/活动状态门槛和 5s 限频 | RootTunControllerTest 覆盖 Magisk 禁止探测/状态查询、停止后禁止探测和 runtime 不存在；RootAuthorizationTest 覆盖限频、签名状态回传、旧会话拒绝；authorization-test 覆盖 Magisk 删除 policy 判 denied |
| B3 | 心跳阈值 5s；watchdog 失联前 24s 不拆拦截，健康检查失败重试；接管 supervisor 继承同一截止时间且不重复采样后立刻失败 | runtime-test 覆盖 2.5s 循环、慢健康检查后恢复且不拆规则、不重启 core；持续核心失联预算耗尽后清理仍通过 |
| M1 | 对旧 identity 的硬链接快照判活，按 identity 串行回收，原子 mv 到唯一 stale 文件后才尝试 ln 获锁；不删除公共锁路径，不再用连续两次读取作保护；回收者的陈旧锁也可回收 | lock-test 十轮双进程竞争均只有一个获锁者且锁内容一致，并覆盖回收进程死亡后重试 |
| M2 | owner.lock 为旧目录时，仅确认 supervisor 的 PID/startTicks/boot_id 不存活后 rmdir；现有健康旧 supervisor 的显式 adopt 仍保留 | lock-test 拒绝清理活 owner；runtime-test 覆盖重启遗留目录后的 start/stop；uninstall-test 从目录锁完成卸载清理 |
| M3 | proxyStop 保留/恢复 watchdog 的卸载监护；自启关闭不影响监护。独立 cleanup 用于 disable/delete 前结束 watchdog | runtime-test 区分 stop 与 cleanup；uninstall-test 在 proxyStop + autostart=0 后通过两次缺失确认删除 R |
| M4 | settings 校验改用 grep -E 和 POSIX ERE；root-tun sh 资产排查未再发现 BRE 的扩展分支/量词；awk 的字面竖线也改成 [\|] 字符类 | boot-test 验证合法双布尔设置及非法设置；authorization-test 验证 Magisk policy；全量 ShellCheck 0.11.0 零告警 |

非阻塞建议逐项处理：

1. 撤权后驻留：清理成功记录单调时间，最多 600s 后退出并释放探测子进程、PID、心跳和锁；
   失败清理继续重试。authorization-test 覆盖期限退出；R/诊断保留供 App 重试，因此到期后再卸载可能残留 R。
2. KernelSU 分支 ABI：维持未知版本/长度/格式为 unknown 的保守判断，不把无法解析当成撤权。
   KernelSU-Next/SukiSU 的实际 magic/版本/stride、撤销后无 su 的报错和漏判风险仍为 W3 真机待核；
   本轮未增加新业务错误码或把连续 unknown 误报为 denied。已有 unknown ABI 与 JVM Executable unavailable 用例覆盖此边界。
3. 卸载后快速重装 UID 变化：仍可能按旧 app.uid 判 denied 并清理，方向安全；真机记录该行为，未扩大本轮范围。
4. private DNS 查询频率：仍每轮读取，5s 缓存属于后续性能优化；本轮以 B3 时延测试证明慢轮次不误接管。
5. core 重启退避：仍由 5min 内 3 次熔断约束；runtime-test 覆盖跨 supervisor 接管的熔断，未加退避策略。
6. 运行中版本混用：尚未引入 runtime 协议版本/自动 adopt 升级。Magisk 的旧驻留脚本不会回传新状态，
   App 可保持 stale，需用户显式 start 安装新版脚本；后台不能为升级而触发 su 授权。该升级场景仍需真机取证。
7. pm uninstall -k：REPORT 的保留数据口径不变；外部 TDD 不在本地输入中，仍待技术负责人在 #24 同步。
8. 完整 APK 证据：本轮 JVM 编译/28 项单测通过；没有 Gradle wrapper 和 Flutter，未证明 assembleDebug，合入前仍需 CI/设备补证。

评审的 12 项真机清单全部保留为待验，宿主模拟不代替下列取证：

1. HyperOS/Android 17 的 am 用户状态、CE 属性，以及不存在的 cmd user 子命令实际输出。
2. toybox grep 的 BRE 分支行为；当前代码已改成 ERE，仍需核实设备工具行为。
3. pm path/list 在不存在、install -r、uninstall -k 下的退出码和输出。
4. KernelSU allowlist 在授权/撤销时的 magic、版本、记录长度和 od 对照。
5. Magisk SQLite 输出和删除记录的检测；撤权后 App 前台确认不反复弹框/toast。
6. APatch package_config 的表头与列格式。
7. KernelSU 未授权时 su 的报错，以及分支 ABI 未识别时 unknown 的诊断。
8. 关闭 su 管道并强停 App 后的 supervisor/watchdog 会话/cgroup 存活。
9. 安装大型 APK/高负载时心跳间隔、接管和 24s 防漏重试时序。
10. #25/#26/#28/#29 各 AC 的抓包/DNS 日志与诊断导出。
11. Android 17 root 身份 cmd notification post 的通知可见性。
12. service.d/su SELinux 上下文下 timeout、nc、od、sha256sum、cksum、setsid、ln、sleep、diff、sed、awk 的可用性。

## PR #31 复审跟进（S1–S3）

本次工作分支为 `feature/root-tun-p0-followup`，基线为 `a42c58f`（`b9fbd4a` 加用户解锁探测超时的小修）。
以下记录本次跟进；其他章节的提交号、43 条 Shell PASS 与 28 项 JVM 测试为上轮返工留档。

| 项目 | 处理 | 对应验证 |
| --- | --- | --- |
| S2：回报过期 | runtime 的 status 输出与 authorization 的签名回报均写入 `bootMs`，使用 `/proc/uptime` 的毫秒值；App 用 `SystemClock.elapsedRealtime()` 比较，常量 `RootRuntimeReport.MAX_AGE_MS = 8000`。每次读取都重新判断年龄，超过 8 秒即失效；无时间字段的旧格式、非法/重复/未来时间同样视为过期，重放旧回报不会刷新期限 | RootAuthorizationTest 经真实本机签名通道验证新鲜回报、8 秒边界、超时、旧格式、异常时间、重放和新回报恢复；RootTunControllerTest 验证新鲜回报可恢复 running，过期与旧格式不能用于 running；Shell 验证签名包含 bootMs，runtime status 输出毫秒字段 |
| S1：Magisk 无回报降频 | Controller 首次发现缺失/过期回报即标 stale；连续 30 秒未恢复后，reconcile 从每秒一次降至每 30 秒一次，由 `ReconciliationPolling` 的常量控制。新鲜回报或显式新命令重置降频。后台始终只消费签名回报，不查询 su，也不因超时调用 stop/start/attach；App 侧授权探测继续排除 Magisk | RootTunControllerTest 用可控单调时间覆盖连续 95 秒无回报：前 30 秒每秒核对，随后仅在第 60/90 秒核对；断言 su 调用数为 0、授权探测禁用、手动检查映射及重置后恢复高频 |
| S3：proxyStop 后降低探测频率 | 同时满足 `run/stop` 存在、`state/status = disabled -`、`state/owned` 已删除才按已 proxyStop 处理，授权探测间隔为 15 秒；运行中及清理未完成仍为 2 秒。模式变化立即重置调度，重新运行不继承旧的 15 秒等待；卸载探测仍每 10 秒一次 | authorization-test 运行真实 watchdog 调度函数，模拟运行→停止→恢复，断言探测时刻为 0/2/4、5/20、35/37/39 秒；同时验证仅有 stop 标记或 stopping+CLEANUP_FAILED 不会降频。原 runtime-test 继续覆盖重复 start/stop/cleanup 及 proxyStop 保留 watchdog |

手动检查沿用 `stale=true + stopping + CLEANUP_FAILED`：现有 UI 展示状态待核及清理风险，用户可重新检测或停止。
缺失回报只能说明运行/规则未获确认，因此不使用会宣称“已恢复直连”的 CORE_RECOVERY_FAILED，也不推断授权已撤销。
新鲜回报经既有 reconciliation 清除该临时错误并恢复真实状态；本次没有新增八态之外的状态或 27 个业务错误码之外的码。
旧格式继续完成原通道交互，但不能作为新鲜运行凭据；升级旧驻留脚本仍需要用户显式启动授权路径。

本次验证日志统一位于 `out/root-tun-p0-followup-*.log`，使用本 REPORT 下列相同的 Shell/JVM 命令。
本次结果：`sh android/root-tun/tests/run.sh` 全部通过（46 条 PASS）；`python3 out/compile-native.py` 编译通过、31 项 JUnit 通过；
ShellCheck 0.11.0（`-s sh -x`）零告警，所有脚本 `sh -n`、ktlint、diff whitespace 与 comment-density 检查通过。
JVM 编译仍使用现有 `out/compile-native.py` 的依赖与桩，不能代替正式 Gradle/APK 或真机验证。
`flutter pub get`、`flutter analyze --no-fatal-infos` 及 Root TUN plugin/provider/view 的 `flutter test` 已尝试，均因 PATH 无 flutter 无法执行；仓库仍无 Gradle wrapper。
三家管理器、HyperOS/Android 17 的实际计时、授权提示和后台进程行为仍须按原真机清单核验。

本次未运行 git add/commit/push，未写入 `.git` 或 `~/.codex`；建议提交分组见 `out/root-tun-p0-followup-commits.txt`。

## P0 followup 第二轮

本轮完整阅读 `/workspace/flclash-pm/PRD-v1.md`、`/workspace/flclash-apk/测试清单-P0.md`、
`/workspace/flclash-docs/qa/p0-diagnostics-answers.md`，在 S1–S3 上继续实现；不修改 `lib/` Dart、`.git` 或 `~/.codex`，不提交、不推送。
以下为本轮口径，覆盖上文旧的探测时序与诊断限制说明。

### 1. 撤权误报与重复事件

- KernelSU/APatch 状态查询的空输出失败（包括 `127 / Executable unavailable`、明确拒绝和超时）只标记 stale，
  保留最后核对的状态，等待 root 签名回报；不再因为查询失败调用 App 侧 stop，也不据此生成 `CLEANUP_FAILED`。
  三种管理器都优先消费新鲜签名回报；Magisk 后台仍完全不查询 su，缺报的 S1 降频行为保留。
- root 回报的 `stopping ROOT_PERMISSION_REVOKED` 表示正在清理，不映射成 `CLEANUP_FAILED`，
  也不提前发出宣称已经直连的撤权弹窗。只有 root 确认清理成功后才进入 `failed / ROOT_PERMISSION_REVOKED`，
  authStatus=revoked、自启关闭；重新检测不把该原因覆盖为“去管理器授权”。真实清理失败仍保留 `stopping / CLEANUP_FAILED`。
- 同一原生启动会话内按错误码保留首次 `lastErrorAt`，重复错误不重复携带事件 code；显式启动或撤权后重试重置去重。
  信息类事件仍正常发出。撤权确认提升 intentRevision，使尚未完成的旧操作不能覆盖失败状态或再次启动网络接管。
- JVM 覆盖 KSU/APatch 查询失败等待回报、签名撤权结果优先、真实 stopping 与失败原因、错误首次时间稳定与新会话重置、
  撤权确认使旧 revision 失效。**原生去重不能替代 Flutter 的跨页面提示去重，详见下方“需要 Flutter 配合”。**

### 2. LAST_SESSION_ABNORMAL_EXIT（US-07 AC2 / K1）

- root 启动时写入 `state/session`（boot_id + 单调时间），正常停止标记 `session-stop=normal`，
  错误停止标记 abnormal；运行会话标记经 status 和签名回报携带。看门狗 fail-open 后的 failed 状态保留会话证据。
- App 在核对到活动会话后保存自己的会话标记。新进程首次获得同一 root 会话的有效回报，且没有正常 stop 记录时，
  发出 `LAST_SESSION_ABNORMAL_EXIT`，并放入 snapshot.warnings。回报仍为 stale、正在清理或缺少新格式标记时不提前报异常。
  正常 stop/确认关闭、显式新启动、不同 root 会话不会误报；运行中的 root 会话照实显示 running，已清理的照实显示 failed/关闭。
  异常退出横幅不会覆盖 `CORE_RECOVERY_FAILED` 等真实失败原因。
- JVM 覆盖强停后同会话重开、等待核对、仅发一次、正常停止、换会话及看门狗清理后的失败。
  runtime shell 覆盖会话字段、normal stop，以及 supervisor/core 同失联后 abnormal 标记与规则清理。

### 3. 撤权时序（#29 AC1）

运行中探测间隔由 2s 改为 1s，仍需连续两次明确 denied；unknown/超时重置确认计数，不当撤权。
管理器查询与 App 签名交互并行，各自总预算 1s。活动 watchdog 每 250ms 消费结果；proxyStop 后仍按 S3 每 15s 探测，
卸载检查仍每 10s。App 的清理确认消费每 250ms 一轮，不等待原有的 5s 限频 su 探测或 operations 锁。
没有新增 App 授权请求；Magisk 的后台探测和核对始终不调用 su。

撤权清理以独立的 `cleanup-owned` 在同一 owner identity/generation 下运行，单次限时 3s；清理优先级列表每个地址族只读取一次，
避免原先反复执行 44 组 rule show。超时/清理失败继续保留风险状态并重试，绝不先报“已恢复直连”。
系统通知异步执行（最多 3s，记录退出码），不阻塞清理结果交接或再次回报。

| 环节 | 典型推算 | 保守软件预算 |
| --- | --- | --- |
| 等下一次活动探测 | 0.5s | 1.5s（含循环相位） |
| 两次明确拒绝、异步结果消费 | 1–1.5s | 3s（含 1s 查询超时边界及调度） |
| 控制锁竞争/下轮重试 | 通常 0s | 2s |
| 清理核心、规则与核对 | 1–2s | 3s 单次预算 |
| 签名清理交接（含一次未送达后的重发） | 通常 <0.1s | 3.5s |
| App 消费 | 0–0.25s | 0.25s |
| 文件操作、事件投递余量 | 少量 | 0.5s |
| 合计：App 显示失败 | 约 3–5s | **13.75s，距 15s 留 1.25s** |

authorization shell 用真实 watchdog 调度/拒绝计数/撤权路径、虚拟时钟模拟最差探测相位、1s 并行慢探测、
控制锁竞争、3s 清理和 250ms App 消费，结果 **8250ms**；另外运行真实 probe-auth 子进程，
验证管理器/App 超时并行在 1.8s 内完成、慢管理器仍为 unknown。runtime shell 原有慢心跳与健康检查不误清理用例继续通过。

上表适用于受支持授权格式能在探测预算内给出明确 denied、系统调度正常、清理能成功的前台场景，属于代码预算与模拟，
不是手机实测值。未知 KernelSU 分支 ABI、连续 unknown、系统进程长时间挂死或真实规则清理失败不伪造撤权成功；
这些情况下仍保留证据。Android 17/HyperOS 上的实际 ≤15s、强停/cgroup 存活和至少两家管理器仍须真机验收。

### 4. 诊断 zip：12 项补采集与有界输出

所有采集组均通过 POSIX sh 的 timeout 执行（1–3s）；最多 6 组并发，4 批预算约 9s，
Kotlin 总采集预算由 9s 改为 15s，专用 RootShell 输出上限由 1MiB 改为 4MiB，其他 shell 调用仍为 1MiB。
每组保留最多 96KiB，先采并输出时钟、开机、授权与撤权留存；日志单项尾部降为 10–16KB，
22 组加重复的 device/restore 段总输出约束在 2.5MiB 内，给 4MiB 留余量。

| 调查文档 # | 本轮证据 |
| --- | --- |
| 1 | date epoch/本地时间、uptime、boot_id，可换算开机秒数与真实时间 |
| 2 | am 用户状态及前后 uptime/退出码、cmd user 实际输出、CE/boot_completed；boot.log 各阶段 elapsedMs |
| 3 | grep BRE/ERE 实测输出、退出码、toybox 版本及 grep 路径 |
| 4 | pm path/list 输出和退出码、数据目录；watchdog 记录非 present 的结果 |
| 5 | KSU stat/头 8 字节和仅本包 UID 对应 app_profile 的 od 字节；首个 denied 时 root 独立留存 allowlist-denied.txt |
| 6 | Magisk 本 UID policy/until 原始行、APatch 表头和本包行；不导出其他 App 的授权记录 |
| 7 | App 最近 64 次 su 调用的时间/类型/退出码/超时/stderr，包括启动可执行文件失败的实际异常；普通身份导出也带入 device.txt |
| 8 | ps/ps -AZ、上下文、loadavg、运行标记；supervisor 单轮超过 1500ms 写 elapsedMs |
| 9 | service.d 列表、入口头部/hash、runtime 目录树（只列名）、安全的设置/UID/开关文件、FlClashRoot logcat |
| 10 | 通知命令 stderr/退出码留存 notification-last.txt 和 boot.log，补 dumpsys notification |
| 11 | su 采集上下文和 service.d 启动时的独立 service-context.txt；实际测试 timeout、nc -w、od、sha256sum、setsid、硬链接、分数 sleep、diff、sed，列出 awk/cksum 等路径 |
| 12 | nft list ruleset；缺失或不可用照实写入 manifest |

新增 `manifest.txt`：22 组逐项列 exit、timeout、truncated、原始 bytes，以及 success/partial/failed。
嵌套命令/文件退出码也保留在证据正文。每批完成即输出证据与完成记录；总超时或中断时，Kotlin 生成缺项为
`not confirmed` 的 manifest，已经采到的前序内容仍保存。RootShell 即使遇到继承 stdout 的子进程未退出，也保留已读数据。
扩大的文本暴露了既有 URL 脱敏正则对超长单词的重复扫描，本轮增加词边界，JVM 用 >1MiB 证据验证归档与脱敏能完成。

采集命令不执行 su、不启动授权探测；仅沿用用户显式导出时、已知 granted 下的外层 root 执行方式，
未授权时以普通身份采集并标出不可读项。普通身份下无法读取 /data/adb，不宣称能突破撤权取证；
撤权当时的快照由仍有权限的 root watchdog 留存，重新授权后可导出。即使 runtime 已删除，Kotlin 仍携带 APK 内授权采集函数，
以本 App UID/检测到的管理器采集原始授权证据，不要求先启动 Root TUN。
不读 app-auth/health.http/核心配置等敏感内容，所有归档文本继续脱敏。

### 5. K7 自启失败通知与延迟重试

- 网络检查最多 **7 次**（首次 + 6 次重试），间隔 **8s**，理想检查时刻为解锁检测后的 0/8/16/24/32/40/48s；
  共享 48s 依赖预算，随后仍只有 10s 启动预算。包或设置异常同样受预算约束；实际慢命令可能使最后一次检查被预算截掉。
  网络就绪前不安装规则、不拉核心；预算耗尽后放弃本次自启、写日志，不在网络恢复后无限重试。
- 配置缺失/不可读或预算耗尽，经清理写入持久 `failed AUTOSTART_FAILED`，root 发送中文系统通知，
  下次打开 App 可从 root 状态/签名回报恢复，沿用首页已有横幅。启动中超时也会结束旧 supervisor 并清理；
  已有健康 running 会话不会被重复 bootstrap 的失败处理拆掉。
- `ROOT_PERMISSION_REVOKED`、`AUTOSTART_ROOT_REVOKED`、`AUTOSTART_FAILED`、`CLEANUP_FAILED` 的 root 通知使用附录 B 中文正文，
  标题为“FlClash Root TUN 状态提醒”，正文保留括号错误码；命令退出码/stderr 不再吞掉。
- shell 覆盖 16s 后网络恢复、仅启动一次、7 次耗尽时无启动/无接管、持久失败与通知，以及中文文案、成功/失败退出码。
  系统通知实际显示/归属与通知权限关系仍须手机确认，退出码 0 不等于用户已看到通知。

### 需要 Flutter 配合

1. **K1 首页横幅无需补代码。** `lib/models/root_tun.dart` 已定义该码，
   `lib/common/root_tun_labels.dart` 已映射文案，`lib/views/dashboard/widgets/network_takeover.dart:360` 的 bannerCodes
   已包含 `LAST_SESSION_ABNORMAL_EXIT`，且读取 snapshot.warnings。本轮原生补齐发出逻辑，真机应复测显示与状态一致性。
   `AUTOSTART_FAILED` 同样已有横幅，K7 不需要新展示分支。
2. **严格“同一会话同一码只弹一次”仍需 UI 去重键配合。** `lib/views/config/root_tun.dart:94` 目前使用
   `epoch:lastErrorAt:state:code`，且 `_shownPrompts` 仅存于 widget State。本轮稳定原生首次时间、重复事件去 code，
   并在清理完成后才发撤权码，已消除本次重复轮询/撤权两阶段造成的重复；但真实错误跨 state、退出再进入设置页或进程重建，
   仍可能再次弹窗。Flutter 需按 root 会话标识 + code 在 controller/provider 层记录已显示提示，跨页面保留，显式新启动时重置；
   不应将每次 lastErrorAt 或 state 变化当成新提示。若要精确跨 App 进程区分 root 会话，后续把原生已有 session 标识纳入共享 snapshot，
   再同步 Dart 模型与 provider 测试；本轮按要求不改 Dart/共享模型。
3. 按新包复测 QA 的 K1/K2/K3/K5/K7/K9 与所有“待 Android 确认”的采集项；
   KSU 分支 ABI、Magisk/APatch 真机授权行为、HyperOS 通知归属/权限及 uninstall -k 的验收口径不由宿主模拟替代。

### 本轮验证与交付

- `sh android/root-tun/tests/run.sh`：**53 条 PASS**，包括新增 notification/diagnostics suite；
  `python3 out/compile-native.py`：**36 项 JUnit 通过**，JVM 17 编译通过。
- `/tmp/shellcheck-v0.11.0/shellcheck -s sh -x`（全部 Root TUN 资产/构建/测试脚本）：零告警；
  全部脚本 `sh -n`、ktlint、diff whitespace、comment-density 通过。
- 已尝试 `flutter pub get`、`flutter analyze --no-fatal-infos`、Root TUN plugin/provider/view/common/model 的 `flutter test`，
  均因 PATH 无 Flutter 未执行。Go/cargo 可用，本轮无 Go/Rust 改动；仓库无 Gradle wrapper，JVM 桩编译不等于正式 APK/真机证明。
- 日志统一为 `out/root-tun-p0-followup-2-*.log`。建议提交分组及逐组文件见
  `out/root-tun-p0-followup-2-commits.txt`；out 内工具/日志不列为提交内容。工作区留待审阅，未运行 git add/commit/push。

## 文件与验证方式

本轮改动：assets/root-tun/{runtime,authorization}.sh；RootRuntime、RootTunController、RootAuthorization；
android/tests/app/root 的 Controller/Authorization 测试；root-tun/tests 的 POSIX sh 模拟及新增 lock-test。
沿用现有 out/compile-native.py 编译入口。
Flutter MethodChannel/EventChannel、八态、27 个业务错误码和 exportDiagnostics ZIP 返回契约保持不变。

在仓库根目录运行：

```sh
sh android/root-tun/tests/run.sh
/tmp/shellcheck-v0.11.0/shellcheck -s sh android/app/src/main/assets/root-tun/*.sh android/root-tun/*.sh android/root-tun/tests/*.sh
java -jar out/check-tools/ktlint.jar android/app/src/main/kotlin/com/follow/clash/root/*.kt android/app/src/main/kotlin/com/follow/clash/plugins/RootTunPlugin.kt android/tests/app/root/*.kt
python3 out/compile-native.py
```

模拟只在 mktemp 目录复制并改写固定路径，使用假的 pm、ip、iptables、nc、magisk；
真实 sh/core 替身进程按记录 PID 结束，不启动宿主 FlClash，不调用宿主网络修改命令。
超时模拟偶尔出现 `Killed` 是 timeout 的预期取证，退出码与断言仍是最终结果。

本机返工结果（2026-10-23）：shellcheck 0.11.0（`-s sh -x`）/sh -n、模拟套件（43 条 PASS）、ktlint、28 项 JVM JUnit、
diff whitespace 和 comment-density 检查通过。
JVM 编译使用 out/check-tools 缓存的 Android/Flutter 依赖与宿主/R/BuildConfig 桩，以 JVM 17 为目标；
**不等于正式 Gradle/targetSdk 37 编译或 APK 验证**。本轮日志位于 `out/root-tun-p0-r1-*.log`。

已尝试但未能执行的仓库检查：

- flutter pub get、flutter analyze --no-fatal-infos、flutter test test/core/protocol_contract_test.dart：PATH 无 flutter。
- android/./gradlew :app:compileDebugKotlin：仓库无 gradlew。
- 本轮未运行 detekt、APK 打包、安装和真机验收；Go/cargo 不涉及改动，未触发其构建。

## 仍保留的方案 B 偏差

mihomo 控制面仍为 127.0.0.1 TCP + token，不是 TDD 的 Unix socket/SO_PEERCRED；新增撤权交接也不代表已实现该 UID 认证协议。
网络恢复沿用命名空间所有权 + 完整文本基线，不是结构化 undo.jsonl；跨切网的真实全局差异按 TDD Q1 保留证据。
Root 侧 status/心跳不等于完整 root-agent Snapshot/事件持久化；可靠配置 reload、Core 数据桥仍属原有后续范围。
本轮没有改动这些已登记的边界，也不以模拟替代 W1/W3/W4/W5 和至少两种 root 方案实测的发布门槛。

## 提交与交付

本轮遵照要求，未运行 git add/commit/push，未写入 .git 或 ~/.codex；HEAD 保持 `e37003d`。
改动留在工作区，建议提交分组与逐组文件清单位于 `out/root-tun-p0-r1-commits.txt`；out 下的日志/工具不作为提交内容。
runtime.sh 的 B1/B3/M1/M2/M3/M4 共用锁、恢复和停止路径，建议同组提交，避免拆出中间不安全状态。
正式交付仍需技术负责人复审、完整 APK 编译和上述真机取证；未请求合并 PR。

## PR #33 评审修复

本节对应 `/workspace/flclash-docs/reviews/2026-10-23-pr33.md` 的 M1、M2、N1、N2，
以本节覆盖上文“首次缺报立即要求清理”及 manifest 原始 bytes 的旧口径。
工作分支为 `feature/root-tun-p0-followup`，HEAD 保持 `f84902d`；未改 Dart/main，未运行 git add/commit/push。

### M1：首次缺报宽限期与状态边界

- `RootTunController.kt` 的 `ReconciliationPolling` 从首次缺报开始计单调时间，宽限期为 **23s = 15s + MAX_AGE_MS(8s)**。
  宽限期内只标 stale，保留状态、运行时间等字段，不生成错误码或 code 事件；新鲜回报重置宽限期和降频计时。
  连续缺报 30s 后每 30s 核对一次的 S1 降频仍保留，Magisk 后台核对不调用 su。
- `RootReconciliation.kt` 统一缺报状态转换：期满后只有最后状态为 STARTING/RUNNING/RECOVERING/STOPPING 才升级为
  stopping+CLEANUP_FAILED；DISABLED 及已清理的 FAILED 继续只标 stale，FAILED 的真实失败原因和首次时间保留。
  授权已知 granted、尚无首份状态时，`checked` 也保留缓存状态，不再立即要求清理。
- 保留闲置回报 15s，而不改为 ≤8s，以免增加已直连/自启失败后的授权探测与进程开销；活动态仍按 1s 回报。
  8s 新鲜度上限继续严格执行，因此闲置回报间隙可能显示 stale，但不会合成清理失败；不延长旧 running 回报的可信期限。
- `RootTunControllerTest.kt` 覆盖冷启 disabled+15s 回报、冷启 running+1s 首报、重启后无 watchdog+disabled，
  三种均收集并断言没有 CLEANUP_FAILED code 事件；运行中长期缺报在 23s 边界升级，且只发一次该错误事件。
  `RootReconciliationTest.kt` 覆盖八态的首次缺报、期满状态边界及已清理失败原因保留。

### M2：失败闲置态统一降低授权探测频率

- `assets/root-tun/runtime.sh` 的 `authorization_interval` 在没有 `state/owned` 且 status 匹配 `disabled*|failed*` 时统一为 15s，
  包括 AUTOSTART_FAILED 和 fail-open 后的 CORE_RECOVERY_FAILED，不再依赖 `run/stop` 标记。
  有 owned 或尚在 stopping 清理时仍为 1s；与 M1 的 23s 宽限期、8s 新鲜度共同使用。
- `tests/boot-test.sh` 在真实 bootstrap 的 AUTOSTART_FAILED 结果后断言间隔为 15s；
  `tests/authorization-test.sh` 补齐无 stop 标记的 disabled/两种 failed 及重新有 owned 时恢复 1s，原调度/撤权时序用例继续通过。

### N1/N2：诊断临时目录与流式截断

- N1：`assets/root-tun/diagnostics.sh` 在 root 身份下覆盖 TMPDIR 为 `$R/tmp`，目录不存在时创建，umask 077 并确保权限 0700；
  `RootRuntime.kt` 的 root 调用不再传入 App cacheDir，普通身份调用继续使用 cacheDir。
  `tests/diagnostics-test.sh` 验证 root 已有目录优先、缺失时创建及权限、普通身份使用 App cache，采集不调用 su。
- N2：移除 `ulimit -f`。每项先以 `head -c 98305` 保存至多 96KiB+1 字节样本，统计后输出至多 98304 字节；
  多出的一个字节用于准确判定 `truncated=yes`。管道继续排空多余输出直到命令退出或 timeout，防止 SIGPIPE 污染真实退出码。
  manifest 的 `bytes` 现在是有界样本大小，`bytes=98305 truncated=yes` 表示原输出至少 98305 字节，不再声称是完整原始大小。
  同一测试补验恰好 96KiB、超过一字节、300000 字节 nft 成功输出、超量且 exit=7、timeout=137，以及 raw/txt 文件大小上限。

### 验收结果（2026-10-24）

| 检查 | 结果 |
| --- | --- |
| `sh android/root-tun/tests/run.sh` | **57 条 PASS**，exit 0 |
| `/tmp/shellcheck-v0.11.0/shellcheck -s sh -x android/app/src/main/assets/root-tun/*.sh android/root-tun/*.sh android/root-tun/tests/*.sh` | **零告警**，exit 0 |
| `python3 out/compile-native.py` | JVM target 17 编译通过，**40 项 JUnit 通过** |
| `java -jar out/check-tools/ktlint.jar` 检查本轮改动的 5 个 Kotlin 文件 | **零告警**，exit 0 |
| `git diff --check` | 通过，exit 0 |
| 全部 16 个 Shell 脚本 `sh -n`、改动 Kotlin 的 comment-density | 通过 |

日志为 `out/root-tun-p0-followup-3-*.log`。`flutter pub get`、`flutter analyze --no-fatal-infos`、
Root TUN plugin/provider/view 的 `flutter test` 均已尝试，因 PATH 无 flutter（exit 127）未能执行；Go/cargo 可用，仓库无 Gradle wrapper。
JVM 使用既有 `out/compile-native.py` 和依赖/桩，不能代替正式 Gradle、APK、CI 或真机验收。

### 后续项与真机验证

- **N3**：本轮不改 watchdog 主循环 0.25s；需要真机比较活动/闲置状态下 CPU、fork 次数及功耗。
- **N4**：本轮不改 `RootPreviousSession`；当前同一 root 会话且 stop:active 时重开 App，仍可能把系统 LMK 回收误判为异常退出。
  后续结合 `ActivityManager.getHistoricalProcessExitReasons` / `ApplicationExitInfo` 区分 LMK 与强停，当前偏差保留。
- **N5**：后续按主题拆分 PR；本轮建议提交为 M1、M2、诊断 N1/N2、REPORT 四组，逐组文件与依赖见
  `out/root-tun-p0-followup-3-commits.txt`，out 下工具与日志不列入提交。
- **撤权时序**：模拟的 8250ms 和此前 13.75s 软件预算不等于手机实测；至少两种管理器、Android 17/HyperOS 的前台撤权 ≤15s，
  以及真实授权探测、清理、通知与调度延迟仍须真机验证。冷启首报/闲置 15s、SELinux 下临时目录权限与 KILL 残留也需随 APK 复测。
