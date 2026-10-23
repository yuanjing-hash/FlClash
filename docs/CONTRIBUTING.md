# FlClash Root TUN 项目：团队分工与交付规范

仓库：yuanjing-hash/FlClash（fork 自 chen08209/FlClash）
目标：在已 root 的 Android 设备上提供 Root TUN 模式（不走 VpnService），并通过 Magisk/KernelSU/APatch 的 service.d 实现开机自启。
交付物：签名 APK、源码 PR、文档。

## 1. 角色与职责
| 角色 | 职责 | 交付物 |
|---|---|---|
| 项目经理（牛马CEO） | 范围、进度、风险、验收；唯一对接老板（静） | 里程碑计划、周报 |
| 产品经理 | PRD、用户故事、验收标准、优先级 | PRD、Issues |
| 技术负责人 | 技术方案 TDD、ADR、接口定义、最终 Code Review | TDD、ADR、Review |
| Android 原生工程师 | root 检测与 su、TUN 启动、ip rule/路由/iptables/DNS、service.d 脚本 | Kotlin/Go/Shell 代码 |
| Flutter 工程师 | 模式开关、设置页、状态展示、平台通道、无 root 降级 | Dart 代码 |
| 测试工程师 | 测试计划、用例、设备矩阵、缺陷管理 | 测试报告 |
| DevOps 发布工程师 | CI、签名、版本号、Release、同步上游 | 流水线、Release |

沟通规则：任何人不 @ 老板、不私下找老板；审批和疑问一律找项目经理，由项目经理汇总请示。

## 2. RACI
| 活动 | 老板 | 项目经理 | 产品 | 技术负责人 | 工程师 | QA | DevOps |
|---|---|---|---|---|---|---|---|
| 需求与 PRD | C | A | R | C | I | C | I |
| 技术方案 | I | A | C | R | C | I | C |
| 任务拆分 | I | A | C | R | C | I | I |
| 编码 | - | I | I | A | R | I | C |
| Code Review | - | I | - | A/R | R(互审) | I | I |
| 测试 | - | A | C | C | C | R | I |
| 发布 | A | R | I | C | I | C | R |
| 验收 | A | R | C | C | I | C | I |

## 3. 研发流程（每一关都有准入和准出）
1. 需求评审：PRD 含 Given/When/Then 验收标准，评审通过后冻结 v1。
2. 技术方案评审：TDD 与 ADR 通过技术负责人和项目经理评审。
3. 任务拆分：GitHub Issues + Milestone + labels，每个 Issue 有负责人和验收标准。
4. 开发：从 main 拉 feature 分支，小步提交。
5. PR + CI：CI 全绿才能请求 Review。
6. Code Review：至少 1 人批准，必须包含技术负责人；不通过就退回开发。
7. QA 测试：按用例和设备矩阵测试；不通过就退回开发。
8. 合并 main：squash merge，需老板经项目经理批准。
9. 发布：打 tag，CI 出签名 APK，发 GitHub Release。

## 4. 代码与分支规范
### 分支
- main 受保护，禁止直接 push，只能走 PR 合并。
- feature/<issue号>-<描述>、fix/<issue号>-<描述>、release/x.y.z、hotfix/<描述>。
- 用 upstream remote 定期同步 chen08209/FlClash。
### 提交（Conventional Commits）
`<type>(<scope>): <描述>`，type 取 feat / fix / docs / refactor / test / chore / ci，例如 `feat(tun): add root tun launcher`。
### PR
- 模板写清背景、改动、测试方式、截图，并关联 Issue。
- 建议每个 PR 改动不超过 400 行，CI 全绿，至少 1 人批准（含技术负责人），squash merge。
### 编码规范
| 语言 | 规范 |
|---|---|
| Dart | Effective Dart，`dart format`，`flutter analyze` 零警告 |
| Kotlin | Kotlin 官方编码约定，ktlint / detekt |
| Go | Effective Go，`gofmt`，`go vet` |
| Shell | service.d 用 POSIX sh，`shellcheck` 零报错，幂等，日志写入文件；脚本统一放在 `/data/adb/service.d`（Magisk/KernelSU/APatch 通用），运行时只读写 `/data/adb/flclash-root/` 下的文件 |
签名密钥只存在 GitHub Secrets 中。

## 5. 测试与质量
测试分四层：单元测试、集成测试、真机手测、回归测试。
设备矩阵：Android 10 只测 Magisk；Android 12 测 Magisk + KernelSU；Android 14 和 15 测 Magisk + KernelSU + APatch。
关键用例：
- 开启和关闭 Root TUN，关闭后网络完全恢复
- 与 VpnService 模式互斥
- DNS 不泄露
- IPv6
- 分应用代理
- 开机自启
- 核心崩溃后自动拉起
- 卸载后清理路由和脚本
- 无 root 设备优雅降级

## 6. 完成定义（DoD）
- [ ] 代码已 Review
- [ ] CI 全绿
- [ ] 新增或更新了测试
- [ ] 文档和 README 已更新
- [ ] 写了 CHANGELOG 条目
- [ ] 至少在 2 种 root 方案上测过
- [ ] 没有新增 lint 警告

## 7. 版本与发布
- 版本号用 SemVer，基于上游版本加后缀，例如 `v0.9.1-root.1`。
- CI 构建签名 APK，GitHub Release 附 changelog。
- 发布必须经老板批准，由项目经理转达。

## 8. 里程碑
| 里程碑 | 内容 | 负责 | 验收 |
|---|---|---|---|
| M0 | 仓库初始化：Issues、分支保护、模板、CI | DevOps | 能出 PR 检查和 APK |
| M1 | PRD + 技术方案 | 产品 / 技术负责人 | 评审通过 |
| M2 | Root TUN 核心 | Android | 真机能连通、无 VpnService |
| M3 | service.d 开机自启 | Android | 重启后自动生效、幂等 |
| M4 | Flutter UI | Flutter | 开关、状态、降级提示齐全 |
| M5 | 测试与首个 Release | QA / DevOps | DoD 全部满足，Release 发出 |

## Codex 使用与调度（省额度）
Codex 规则（省额度）：写代码、编译、调试、读大段代码、写长文档这些重活一律交给 Codex，你自己只负责拆任务、写清楚给 Codex 的指令、检查结果。Codex 用的是老板自己的中转，模型 gpt-6.1-sol，推理强度 xhigh，已经配好，不要改 ~/.codex 里的任何文件，也不要读或输出 key。
1. 要用 Codex 之前，先用 SendToAgent 发一条给牛马CEO 申请：写清楚任务一句话、工作目录、预计多久。等牛马CEO 回复"可以开始"再跑。全组同时最多 3 个 Codex，由牛马CEO 统一调度。
2. 开跑方式只有一种：Shell 里运行 `/home/box/.local/bin/codex-run -C <工作目录> "<给 Codex 的完整指令>" > /workspace/codex-logs/<你的角色>-<时间>.log 2>&1`，block_until_ms 设为 0 放到后台，然后直接结束这一轮。不要直接调用 codex，不要自己开多个。
3. 等待期间什么都不做：不要轮询、不要 sleep、不要反复看日志或 codex-status。任务结束时系统会自动通知你。
4. 收到完成通知后，看日志末尾，核对结果，然后用一条 SendToAgent 告诉牛马CEO：成功还是失败、改了什么、下一步要不要再用 Codex。说完就结束。
