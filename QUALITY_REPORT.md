# 质量证据契约

本文件定义 `1.0.0 (1)` 的质量判定方法，不手工保存会随代码变化而过期的“当前已通过”数字。产品行为的唯一规范性事实源是 [CURRENT_PRODUCT_BASELINE.md](CURRENT_PRODUCT_BASELINE.md)；本文件只规定如何用可重复证据验证它。

## 唯一本地总门槛

```sh
./scripts/verify_release.sh
```

该命令必须在同一份源码上完整执行：

1. Swift 格式门槛、Release 构建、Xcode 静态分析、临时签名校验和严格并发编译。
2. 原生 XCTest 真实执行、零失败、零跳过以及覆盖率下限。
3. XCUITest 使用全新 DerivedData 和隔离数据真实驱动 macOS 窗口；只编译 UI 测试不算通过。
4. 交互、气泡层级、画布性能、架构边界、持久化与布局验证器的确定性正反例、视觉/辅助功能渲染、连续两轮截图逐字节可重复性和 App Store 截图规格审计；架构审计不得以源码字符串代替运行行为。
5. Sandbox、用户选择只读权限、app-scoped security bookmark、隐私清单、图标资产、禁止网络/自更新/高风险 API 边界；源码、entitlement 与签名产物必须一致。
6. 当前产品基线、持久化字段与隐私披露的双向一致性，以及历史交接中的冲突要求扫描。
7. 测试声明数从源码动态计算，并与当次 `.xcresult` 的通过数严格相等；稳定文档不得手写易过期计数。
8. 由总门槛直接编排的公开仓库候选审计：公开文档链接、仓库路径边界、敏感文件和高风险代码模式。

所有门槛通过后，脚本才会生成 `.artifacts.noindex/quality-evidence.json`。该文件包含执行时间、macOS/Xcode/架构、XCTest 和 XCUITest 通过数、源码 SHA-256 指纹及明确的声称边界。它是当次本地证据，不提交到 Git，也不会被旧结果静默复用。

## 结论规则

- 任意门槛退出码非零，整体结论就是不通过；不得用其他优势抵消。
- `.xcresult` 必须记录 `Passed`、零失败和零跳过；“能编译”不等于“执行通过”。
- 构建日志中的任何 `warning:` 或 `.xcresult` 中的任何运行时警告都会阻断发布；不使用警告白名单。Xcode 27 Runner 的 Thread Performance Checker 误报在共享 Test Plan 中从检查源关闭，产品性能仍由独立可执行审计覆盖。
- PNG/JPEG 存在不等于视觉通过；自动对比度、遮挡、固定 2× RGB 输出、两轮逐字节可重复性与截图规格检查必须通过，仍保留人眼设计评审。
- 临时签名、未签名 Archive 和本地 Gatekeeper 结果不得写成 App Store 可上传证据。
- 本地通过不等于 GitHub Actions 已通过；只有远程工作流记录能证明远程 CI。
- GitHub 托管工作流通过同一 `verify_release.sh` 并行运行 `--hosted-ci-core` 与 `--hosted-ci-runtime`：两者共同强制构建、静态分析、XCTest、核心覆盖率、完整 XCUITest 编译、行为/性能/视觉/安全/资产审计；任何一个矩阵失败都不能形成远程通过结论。托管桌面上的 UI 编译不会被写成 XCUITest 执行通过，真实 UI 与 UI 覆盖率仍只能由默认门槛在受信任交互式 macOS 会话生成。
- 自动化不代替真实用户研究、Apple 人工审核或尚未执行的专项硬件矩阵。
- 总门槛验证布局算法、迁移和验证器契约；某位用户的已安装布局只能在显式指定真实 `布局.json` 时验收，文件缺失绝不得记录为通过。
- 架构边界检查只证明模块所有权、依赖方向和复杂度上限；保存布局检查只证明当前 JSON 数据满足几何不变量。二者都不能替代 XCTest、XCUITest、视觉验收或人工使用。

## 需要独立留存的外部证据

- 正式 Bundle ID、Developer Team、Apple Distribution 证书、描述文件、signed Archive 和 Validate App 结果。
- GitHub 项目所有者的提交身份、远程仓库、保护规则、Actions 记录和 Release 历史。
- 真实 macOS 13、Intel Mac、VoiceOver、多显示器、睡眠唤醒和长时间运行验收。
- 正式签名 App 中的用户文件夹“选择—扫描—退出—重启恢复—移除授权”全链路，以及登录项“注册—系统批准—注销/重启静默启动—取消注册”全链路；模型测试、临时目录重建和 ad-hoc 构建都不能替代这两项系统集成证据。

当前发布所有者的操作入口见 [RELEASE_READINESS.md](RELEASE_READINESS.md)。
