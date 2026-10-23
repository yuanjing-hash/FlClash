# Root TUN 方案 B spike

让独立 root mihomo 创建 TUN、自动加路由，绕过 VpnService。当前已完成双架构构建与离线检查，
**尚无 Android 真机流量证据，不能宣称端到端已跑通**。源码依据与本机结果见 [REPORT.md](REPORT.md)。

前提：Android 10 / API 29+、arm64 或 x86_64、已授权的 adb、可用的 `su -c`（首测 Magisk），
内核支持 TUN / UID policy routing，SELinux 允许 root 进程操作 TUN、netlink 和网络。
先关闭现有 VPN；测试期间保持网络稳定。脚本不修改 SELinux、私人 DNS 或系统持久配置。

```sh
# Linux x86_64 构建机：Go 1.27.3，NDK r27c；已有缓存可直接构建。
sh spike/root-tun-b/build.sh
# 主机需 Android platform-tools；不需要 adb root，也不需要设备自带 curl。
sh spike/root-tun-b/run-spike.sh DEVICE_SERIAL
```

全新构建机可设置 `ANDROID_NDK_HOME`，或下载到已忽略的缓存目录：

```sh
cd spike/root-tun-b
mkdir -p .cache
curl -fL https://dl.google.com/android/repository/android-ndk-r27c-linux.zip -o .cache/ndk.zip
unzip -q .cache/ndk.zip -d .cache
sh build.sh
```

`build.sh` 通过 HTTPS 获取 fork 的 FlClash 分支并检出子模块锁定 SHA，不初始化空子模块、
不修改 `.gitmodules`。`bin/`、`.cache/`、`logs/` 均不提交。
shellcheck 已安装在 `.cache/tools/shellcheck-v0.11.0/shellcheck`，可用以下命令复查：

```sh
.cache/tools/shellcheck-v0.11.0/shellcheck -s sh ./*.sh
```

默认 `DIRECT`。只需在 `config.yaml` 的 `proxies` 填节点，并把 `OUT.proxies` 改为该节点名。
保留 TUN 名、路由表、优先级、控制地址和 secret，脚本依赖这些固定值。
默认访问 `1.1.1.1:80`，Host 为 `one.one.one.one`；如被运营商拦截，可设置
`SPIKE_TEST_IP`、`SPIKE_TEST_HOST` 换成可访问的 HTTP 站点。

配置选择 `gvisor`，编译带 `with_gvisor`：TCP/IP 在用户态处理，先减少对 Android 内核网络栈差异的依赖，
这次不评估性能。显式配置数字 IP 的 DNS 上游及节点域名解析器，不依赖 Android 不存在的
`/etc/resolv.conf`。控制端只绑定 `127.0.0.1:19090`，DNS 监听 loopback，未开启代理入站端口。

脚本经 adb stdin + `su` 把文件传入 `/data/adb/flclash-root/`，解决普通 adb shell 无权向
`/data/adb` 执行 `adb push` 的问题；设备上的文件写入仅限此目录。启动前要求优先级 9000–9010、
表 20220 和接口 FlRootB 空闲。只对本次启动并核对 PID、启动时间、可执行路径的进程发信号。

| 检查 | 含义 |
| --- | --- |
| root / Android / ABI | 确认设备、API、su 身份及 Magisk / KernelSU / APatch 迹象 |
| baseline / running | 保存 IPv4/IPv6 rule、所有路由表、iptables-save、ip6tables-save、ip link |
| TUN_UP / no_TRANSPORT_VPN | 接口 UP，connectivity dump 无 VPN transport 迹象；已有 VPN 时拒绝开始 |
| nonroot_HTTP_TUN_and_controller | 探针降为 UID/GID 2000、附加 inet 组 3003；API 精确匹配其源端口、目标和 TUN 类型，再收到 HTTP 2xx/3xx |
| DNS_UDP/TCP_53_hijack | 对无真实 DNS 服务的 TEST-NET 地址 `203.0.113.53:53` 查询，要求收到正确 fake-ip A 记录 |
| normal_restore | SIGTERM 后七类快照恢复；比较时只去除注释、计数器及路由 expires 倒计时 |
| SIGKILL_restore | 强杀后原始残留检查，**有残留即 FAIL**；保留证据后仅删除预先确认空闲范围内的测试规则 |
| cleanup_restore | 有限清理后再次对比全部快照，不覆盖整份系统路由或防火墙 |
| SELinux / AVC | 记录 getenforce、dmesg、logcat；要求 Enforcing 且无新增 avc denied；读不到日志也不能当通过 |

完整命令输出、快照、diff、Core 日志与 PASS/FAIL 汇总写入 `logs/<时间>-<设备>-<pid>.log`；
同名目录保留原始快照、SELinux 日志与归档。任一 FAIL 返回非零，SIGKILL 残留也计入其中。
同时启动其他 VPN/路由管理器会使恢复对比与清理的所有权假设失效，测试期间不要启动它们。
adb 中断后不要直接删除锁或覆盖二进制：先检查设备目录中的 PID、Core 日志、七类快照，
确认原测试驱动及其 Core 已退出再处理。脚本不会清空系统日志、flush 系统防火墙或恢复整个系统快照。

风险：SELinux/OEM 策略可能阻止 netlink、TUN、执行或降 UID；SIGKILL 会跳过路由清理；
9000–9010 比常见 Android VPN 规则更早，可能接管别的 VPN，必须按实际 `ip rule` 判断优先级。
Android 私人 DNS（DoT/853）和应用 DoH 不受 53 劫持控制；先手动关闭严格私人 DNS再测 53，另测 853。
这份最小配置仅验证 IPv4，IPv6 可能直连；UID 0 全部排除，root 应用流量也绕过。
探针保留 su 的 SELinux 域，不能代替真实 App UID/域、Wi-Fi/蜂窝切换、休眠及各 root 方案的测试。

开机不打开 App：后续由 Magisk 模块 `service.sh`（KernelSU/APatch 对应 late-start 服务）
在 `/data/adb` 可用后启动此独立进程；等待网络、监控退出、处理崩溃残留并重启。
配置与二进制保存在此设备目录，TUN/路由归 root 进程拥有，因此无需 Flutter、App 进程或 VPN 授权 UI。
本 spike 不安装开机模块；解锁前接管时机、监督进程及重启恢复仍需实机验证。
