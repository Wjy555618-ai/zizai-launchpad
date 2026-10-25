# 发布准备状态

本文件是 `1.0.0 (1)` 唯一的发布操作入口，但不手工复制会过期的测试数字。产品基线见 [CURRENT_PRODUCT_BASELINE.md](CURRENT_PRODUCT_BASELINE.md)，质量判定方法见 [QUALITY_REPORT.md](QUALITY_REPORT.md)。

## 代码与产品门槛

发布前必须从当前源码重新执行：

```sh
./scripts/verify_release.sh
./scripts/verify_unsigned_archive.sh
./scripts/audit_public_repo.sh
```

`verify_release.sh` 会真实运行 XCTest 和 XCUITest，不以编译代替执行；全部成功后生成与当前源码指纹绑定的 `.artifacts.noindex/quality-evidence.json`。任意一条命令失败就停止发布。

其中 `audit_public_repo.sh` 只适用于包含完整 GitHub 文档与 `.github` 配置的源码仓库；精简的 App Store 接力包不携带该脚本，按入口文档执行前两项即可。接力包自身由源码仓库中的 `verify_app_store_handoff.sh` 在干净解压目录内复验。

## GitHub 公开

本地代码只能证明“公开候选集可审计”。成熟的远程开源交付还必须由项目所有者完成：

1. 使用真实作者身份建立首次提交和可追溯历史。
2. 创建远程仓库，启用 Private Vulnerability Reporting 和必需分支保护。
3. 推送后确认 GitHub Actions 的构建、分析和真实 XCUITest 全绿。
4. 在同一提交上创建签名 tag 和 Release，并附上校验和。

没有远程记录时，不得把本地源码目录宣称为“已运营的成熟 GitHub 项目”。

## Mac App Store

代码侧 Archive 入口是 `scripts/archive_app_store.sh`。正式提交仍必须由发布者提供最终 Bundle ID、Apple Developer Team、Apple Distribution 证书和描述文件，并在 App Store Connect 完成 URL、联系人、SKU、价格和销售地区。

配置正式身份后必须完成 signed Archive、Validate App 和上传处理。未签名或 ad-hoc 产物只用于本地审计，不得分发或上传。工程可以消除可自动验证的风险，但任何人都不能承诺 Apple 人工审核一次通过。

## 专项环境证据

自动化通过后仍需留存真实 macOS 13、Intel Mac、VoiceOver、多显示器、睡眠唤醒和长时间运行记录。这些是发布风险证据，不得从 Universal 2 编译或模型测试中推断。

正式签名产物还必须逐项完成两条由系统状态参与的人工验收链路：

1. 在设置中选择额外应用目录，确认扫描结果；完全退出并重启，确认 app-scoped 只读安全范围书签恢复；移除授权后确认该目录不再参与后续扫描。
2. 开启登录启动并完成系统批准，注销或重启后确认应用以 accessory 身份静默准备且不抢焦点；用户主动打开后窗口立即出现；关闭登录启动后确认系统注册已移除。

仓库内测试验证授权生命周期、失败恢复与登录项事务语义，但没有正式身份和真实系统批准时，不得把模型或 ad-hoc 结果写成上述系统集成路径已经通过。

## 结论边界

- 本地三个门槛全绿：可以宣称“代码与产品候选通过”。
- 再加远程 Actions、签名 tag 和 Release：可以宣称“GitHub 发布闭环完成”。
- 再加正式签名 Archive 和 Validate App：才能宣称“技术上可提交 Mac App Store”。
