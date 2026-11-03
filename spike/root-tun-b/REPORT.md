# 方案 B 验证记录

2026-10-23，worktree `feature/spike-root-tun-b`。沿用上一轮的配置、构建脚本及 Go 探针，
补全 adb 驱动、设备检查与说明。只修改 `spike/root-tun-b/`；没有修改子模块或 `.gitmodules`。

## 源码与防回环

使用 https://github.com/chen08209/Clash.Meta 的 `FlClash` 分支，
SHA `8380d0e7462f061a964323e9bf3129a236fcc5d5`，与当前子模块 gitlink 一致；未使用上游替代。
源码保留在 `.cache/source/`，依赖是 `github.com/metacubex/sing-tun v0.4.27`。

- fork [`listener/sing_tun/server.go`](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/listener/sing_tun/server.go#L333)
  启动默认接口监控，将 `auto-detect-interface` 接入 dialer；
  [`component/dialer/bind_linux.go`](https://github.com/chen08209/Clash.Meta/blob/8380d0e7462f061a964323e9bf3129a236fcc5d5/component/dialer/bind_linux.go#L14)
  通过 `SO_BINDTODEVICE` 绑定出口。Android 也编入 Linux 文件。
- sing-tun `tun_linux.go` 的 `rules()`（约 600–660 行）将配置的 `exclude-uid: [0]`
  变成 `uidrange 0-0 goto 9010`，跳过本次 TUN 查表；其他本地 IPv4 流量走表 20220。
  这是配置显式提供的 root 防回环，不是 mihomo 按自身 PID 自动排除。必须用非 root 探针验证接管。
- `auto-route: true`、`auto-redirect: false` 下没有自动设置全局 routing-mark，
  sing-tun 也没有通用的 `not fwmark <mark>` 自排除规则。
  `server.go` 约 520 行仅在 auto-redirect mark 模式才设置 `DefaultRoutingMark`；
  `mark_linux.go` 的 `SO_MARK` 能力不代表这份配置启用了它。
- `tun_linux.go` 约 745 行的 Android `0x20000 protectedFromVPN` 分支用于和检测到的 Android VPN 协调，
  不应当作此 root 进程的防回环。当前测试拒绝已有 VPN。fork 的 `server_android.go`
  `buildAndroidRules()` 是空实现，不能假定 Android 包名排除会自动完成；数值 UID 排除直接传给 sing-tun。
- `unsetRules()` 在正常关闭时删除 9000–9010 内的规则；SIGKILL 没有退出处理。
  TUN fd 关闭后网卡和关联路由通常由内核移除，policy rules 可能残留。
  因此启动前检查整段优先级空闲，强杀后先取证，再只删除这段测试规则，并重新核对快照。

## 构建与本机结果

Go `go1.27.3 linux/amd64`，NDK r27c / clang 18.0.3，`with_gvisor`、`-trimpath`、`-s -w`。
arm64 使用 `GOOS=android CGO_ENABLED=0`；Android amd64 的外部链接使用
`GOOS=android CGO_ENABLED=1` 和 NDK 的 `x86_64-linux-android29-clang`。
两者均为 ELF64 PIE，解释器 `/system/bin/linker64`；x86_64 仅依赖系统 `liblog.so`、`libdl.so`、`libc.so`，
没有 glibc 依赖。另附不依赖 libc 的静态 Linux syscall 探针，按架构编译供 Android 内核执行。
DNS 显式配置，所以不靠 libc/Go 默认解析器查找 `/etc/resolv.conf`。Android 加载与执行仍待设备验证。

| 文件 | 大小（bytes） | MiB |
| --- | ---: | ---: |
| `bin/arm64/mihomo` | 62,062,886 | 59.19 |
| `bin/x86_64/mihomo` | 66,848,384 | 63.75 |
| `bin/linux-x86_64/mihomo` | 60,375,200 | 57.58 |

构建日志及 SHA-256：`logs/build.log`、`logs/build-manifest.txt`。
Android 两个 mihomo 的 SHA-256 分别为：

```text
arm64   6d0aec62c9d75d07abbe724a76ddf775ed0794bf7269f652e68bee2b2ded6ecd
x86_64  1a247cfe8cbada7900bececbb792487d9881b6d6866e31be2e80db8df6007f7d
```

- 主机/设备脚本：POSIX `sh`，`sh -n` 与本地安装的 ShellCheck 0.11.0 全部通过，零诊断。
- Go 探针：gofmt、双架构编译、`go vet` 通过；控制接口鉴权及 DNS 报文解析已在隔离环境实际执行。
- Linux：user/network namespace 可用，宿主没有 `/dev/net/tun`；在私有 mount namespace 创建该节点返回
  `Operation not permitted`。**auto-route 流量冒烟跳过**，未修改宿主网络。
- 另在独立 network namespace 中，对原配置运行 mihomo `-t` 成功；仅在临时配置关闭 TUN，
  把 TEST-NET 地址配置到该命名空间的 loopback 并绑定 DNS 后，`/version` 鉴权及 UDP/TCP fake-ip 探针通过。
  这是控制/DNS 报文验证，不是 53 劫持或 TUN 流量验证。证据：`logs/linux-smoke.log`。
- 无 adb / root Android 设备；运行主机入口得到预期的 `FAIL prerequisite: missing adb`，日志已落盘。
- 未安装 Flutter，`flutter pub get`、`flutter analyze --no-fatal-infos`、
  `flutter test test/core/protocol_contract_test.dart` 均因找不到命令未执行；没有更改 Flutter/Core 集成代码。

## 必须补上的设备证据

Magisk Android 10+ arm64 真机及 x86_64 root 模拟器上运行 `run-spike.sh`，取得 TUN UP、无 VPN transport、
非 root HTTP 与 API 源端口匹配、UDP/TCP 53 劫持、SELinux/AVC、SIGTERM 恢复和 SIGKILL 残留的原始日志。
还要用真实应用验证其 UID/SELinux 域、私人 DNS/853、IPv6、Wi-Fi/蜂窝切换及休眠；
KernelSU/APatch、开机未打开 App 与解锁前阶段需要分别复测。
当前结论是源码与构建支持方案 B，端到端可行性仍以这些设备证据为准。

## 提交环境限制

原 worktree 的 Git 元数据指向 `/workspace/FlClash/.git/worktrees/android`，其文件系统只读。
`git add` 报无法创建 `index.lock`，因此无法直接更新该 worktree 的索引和分支。
在本目录的 `.cache/commit.git` 中保存基于原 HEAD 的独立本地提交，
可用 `git --git-dir=spike/root-tun-b/.cache/commit.git show HEAD` 审阅；
`logs/verification.patch` 与 `logs/verification.bundle` 保留可移交的提交产物。
它们不等于原分支已提交；原 worktree 中的交付文件仍显示为未跟踪，没有 push。
