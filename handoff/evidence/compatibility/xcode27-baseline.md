# Xcode 27 兼容性基线

> 历史调查记录：本页保存 2026-10-08 修改前的限制与决策依据，不是当前产品状态。当前唯一规范见仓库根目录的 `CURRENT_PRODUCT_BASELINE.md`；当前可重复验证结果见 `.artifacts.noindex/quality-evidence.json`。

- 检查时间：2026-10-08（Asia/Shanghai）
- 主机：MacBook Pro (Mac14,7)，Apple M2，16 GB 内存
- 系统：macOS Tahoe 26.7.1 (25G241)
- Xcode：27.0 (27A266a)
- 当前选中开发目录：`/Applications/Xcode.app/Contents/Developer`
- macOS SDK：27.0
- Icon Composer：`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`
- 可用数据卷空间：约 80 GiB

## 当时观察到的项目限制

- `Resources/Info.plist` 将 `LSMinimumSystemVersion` 设为 `26.0`。
- `scripts/build.sh` 将 Swift 目标写死为 `arm64-apple-macosx26.0`。
- `scripts/install_on_mac.sh` 拒绝 macOS 26 以前系统。
- 当前产物仅包含 Apple Silicon 架构。

## macOS 13 只读编译检查

使用 Xcode 27、macOS 27 SDK，分别对 `arm64-apple-macosx13.0` 和 `x86_64-apple-macosx13.0` 执行源码 `-typecheck`。两个架构返回相同的 API 可用性阻塞：

1. `onChange(of:initial:_:)` 需要 macOS 14。
2. `NSCursor.frameResize(position:directions:)` 需要 macOS 15。
3. `glassEffect(_:in:)` 需要 macOS 26。

没有发现架构专属的编译错误。这支持以一个统一兼容层实现 macOS 13 起步和 Universal 二进制，但在实际修改、双架构构建与真实旧系统运行之前，不能宣称已兼容。

## 已确认实施方向

- 主开发环境保持 macOS 26.7.1 + Xcode 27。
- 应用最低系统优先设为 macOS 13。
- macOS 26 及以上使用 Liquid Glass；macOS 13–15 使用原生材质降级，不复制两套产品界面。
- 构建同时验证 `arm64` 和 `x86_64`，成功后生成 Universal 产物。
- 不把编译通过冒充为真实旧系统运行验证。
