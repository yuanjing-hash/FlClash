## 标题与关联 Issue

- PR 标题使用 Conventional Commits：`<type>(<scope>): <描述>`，例如 `ci(android): prepare root apk builds`。
- 关联 Issue：Closes #

## 背景与改动

说明问题、改动后的行为及范围；涉及 UI 时附截图。

## 验收标准

列出关联 Issue 中的 Given / When / Then 场景及验证结果。

## 测试清单

- [ ] `dart format --output=none --set-exit-if-changed lib test tool plugins setup.dart`
- [ ] `flutter analyze --no-fatal-infos`
- [ ] 相关 Flutter / Dart 测试通过
- [ ] Go core 检查通过（适用时）
- [ ] Android 单元测试通过（适用时）
- [ ] 已记录真机测试的设备、Android 版本和 root 方案（适用时）
- [ ] 文档及 changelog 已更新，或说明不适用原因
- [ ] CI 全绿；未运行的检查已说明原因

测试记录与未验证项：

## 技术负责人 LGTM 记录

- 技术负责人 GitHub 用户名：
- Review / LGTM 链接：
- 确认日期：
- [ ] 已获得技术负责人批准（以 GitHub Review 记录为准）
