# Android Root TUN：方案 B 的 P0 后续实现

工作分支：`feature/root-tun-p0`；基线：`feature/root-tun-native@8f38fc6`（PR #22 二次复审通过）。
本轮完成 #25/#26/#28/#29 的代码与宿主模拟，以及复审中的非阻塞建议。
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
  core 的 PID、API、TUN 和网络规则健康时交给新 supervisor；否则清理并进入 `failed(CORE_RECOVERY_FAILED)`。
- core 崩溃恢复保留接管及 DNS/IPv6 防漏规则，只重启 core；IPv4 FCR_OUTPUT 增加非 TUN 出口拒绝规则，
  防止 TUN 消失后回落到物理网络。恢复失败才 cleanup/fail-open。恢复起止单调时间写入 supervisor.log。
- 5 分钟崩溃窗口持久化在 R/run，跨 supervisor 接管保留；第 3 次进入 CORE_CRASH_LOOP。
  旧 boot 的 PID、网络所有权和崩溃记录不被当成当前 boot 的资源。
- watchdog 的退出 trap 仅释放自己的 PID、探测子进程和锁，不拆正在运行的规则。正常 stop 结束 supervisor/core/watchdog 和已记录的 boot 任务；
  失败态保留卸载监护。watchdog.log 按当前/上一份 2×1MiB 轮换。

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
- runtime 等待 boot_completed 最多 120s，等待用户 0 解锁最多 300s；每 2 秒重查，解锁查询本身有超时。
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
| App 存活 | App UID 执行短超时 `su -c 'id -u'`，探测间隔约 2s + 至多 1s 执行；连续两次明确拒绝才发 revoked | 超时、可执行文件不可用和无法分类的失败为 unknown；实际管理器拒绝输出待 W3 |
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
端口/token 在 App 私有目录持久化并配置到 R；显式重试时轮换 token，拒绝旧会话的清理确认。
App 重建可接收此前的清理结果；App 强停时靠管理器记录独立清理。
撤权后的 watchdog 保留结果交接与卸载监护，显式 stop/disable 才结束。业务错误仍仅使用附录 B 的 27 个码。

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

## 文件与验证方式

主要改动：assets/root-tun/{runtime,authorization,service.d,diagnostics}.sh；RootRuntime、RootTunController、
RootAuthorization、RootReconciliation、RootTunPlugin；android/tests/app/root 的两个新测试类；
root-tun/tests 的 POSIX sh 模拟；out/compile-native.py 增加新测试类。
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

本机结果（2026-10-23）：shellcheck/sh -n（13 个脚本）、模拟套件（32 条 PASS）、ktlint、24 项 JVM JUnit、
diff whitespace 和 comment-density 检查通过。
JVM 编译使用 out/check-tools 缓存的 Android/Flutter 依赖与宿主/R/BuildConfig 桩，以 JVM 17 为目标；
**不等于正式 Gradle/targetSdk 37 编译或 APK 验证**。日志位于 out/root-tun-p0-{shell-tests,native-tests,ktlint}.log。

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

已尝试按 issue 创建 Conventional Commit，但 `git add` 无法创建
`/workspace/FlClash/.git/worktrees/android/index.lock`：`Read-only file system`。
因此没有新提交，HEAD 仍为 8f38fc6；没有绕过 hook，没有 push。

改动保留在工作区，完整 patch（含新增脚本/测试和 out/compile-native.py）为 `out/root-tun-p0.patch`。
补丁已在临时的 8f38fc6 基线通过 git apply 检查，应用后的 22 个文件与工作区逐字节一致。
预期提交分组记录在 `out/root-tun-p0-commits.txt`：

1. feat(android): add independent root tun watchdog (#25)
2. feat(android): clean root tun after confirmed uninstall (#26)
3. feat(android): harden service.d autostart and upgrades (#28)
4. feat(android): clean root tun on permission revocation (#29)
5. fix(android): address root tun review suggestions

结构自查覆盖：runtime 的 owner/control 锁与代际接管、只读慢探测任务、网络清理唯一职责、boot 入口/设置事务、
App 授权探测与签名结果交接、Controller recheck 与通道参数边界；未发现本轮需要另行重构的责任归属问题。
正式交付仍需技术负责人 Review、CI 和上述真机取证；未提交或请求合并 PR。
