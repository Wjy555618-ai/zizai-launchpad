## 改动目的

说明用户问题、根因和本次最小完整修正。

## 实现与边界

- 实现：
- 明确不做：
- 数据或迁移影响：
- 隐私或权限影响：

## 验证

- [ ] `xcodebuild test -project "自在启动台.xcodeproj" -scheme "自在启动台" -destination "platform=macOS"`
- [ ] `./scripts/verify_release.sh`
- [ ] 独立 `自在启动台-UI` 测试目标可以由发布门槛成功编译，常规方案未误启动 Runner
- [ ] 新增或修正了对应回归用例
- [ ] 深浅色、降低动态效果、降低透明度和紧凑窗口的可见影响已检查
- [ ] 不含密钥、证书、用户路径或未脱敏数据
