# 参与贡献

感谢你帮助改进自在启动台。本项目把“交互稳定、本地隐私、可验证”放在功能数量之前。

## 开发环境

- macOS 13 或更高版本。
- 完整 Xcode；当前基线在 Xcode 27 验证。
- 不需要第三方依赖或服务端。

## 提交修改

1. 先阅读 [README.md](README.md) 和 [ARCHITECTURE.md](ARCHITECTURE.md)。
2. 保持 `Sources/`、`Resources/`、`Tests/` 和 `自在启动台.xcodeproj` 之间的单一工程关系，不要创建平行版本或第二个 App Target。标准 XCTest Target 必须保持可运行，独立 `自在启动台-UI` 方案必须保持可编译且在 CI 中真实执行。
3. 不要引入不必要的网络请求、追踪 SDK、沙盒临时例外或高权限 helper。
4. 新增交互逻辑时，优先把纯计算放到 `InteractionGeometry`，并补充对应审计用例。
5. 修改状态结构时，保留对旧布局的迁移路径，不得静默丢弃用户的别名、隐藏状态或分组归属。

## 代码风格

仓库使用 Apple `swift-format`，配置位于 `.swift-format`。

```sh
xcrun swift-format format --in-place --recursive Sources Tests
xcrun swift-format lint --strict --recursive Sources Tests
```

禁止强制解包、`try!` 和隐式解包可选值；必须使用时应在评审中说明不变量和失败行为。

## 验证

至少运行：

```sh
xcodebuild test \
  -project "自在启动台.xcodeproj" \
  -scheme "自在启动台" \
  -destination "platform=macOS,arch=$(uname -m)"
./scripts/verify_release.sh
./scripts/audit_public_repo.sh
```

如修改了视觉或动效，还需要人工检查深色/浅色、降低动态效果、降低透明度以及紧凑窗口。自动测试通过不等于视觉验收完成。

端到端界面测试单独运行：

```sh
./scripts/run_ui_tests.sh
```

它要求测试 Mac 的 Xcode UI Automation 正常工作。CI 使用独立硬门槛真实执行；Runner 连接失败、超时或 0 项执行都不能视为通过。
