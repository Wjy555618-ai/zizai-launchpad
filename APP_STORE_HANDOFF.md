# 自在启动台 App Store 首发版接力说明

## 给接手发布的开发者

这是“自在启动台”准备首次提交 Mac App Store 的唯一项目接力包。请先完成包内校验，再从当前产品基线继续工程化与提交流程。不要寻找、恢复或合并任何更早的安装包、构建产物或版本记录。

## 唯一版本口径

- 发布名称：App Store 首发版
- Marketing Version：`1.0.0`
- Build：`1`
- 唯一入口：本文件
- 唯一文件清单：`SHA256SUMS`
- 唯一交接清单：`APP_STORE_HANDOFF_MANIFEST.json`

包内已包含唯一的 `自在启动台.xcodeproj`。`Resources/Info.plist` 不再写死发布标识，而是从 Xcode Release 配置读取 Bundle ID、`1.0.0` 和 Build `1`，禁止另建工程或另写一套版本号。

## 先做什么

1. 在包根目录运行：

   ```sh
   shasum -a 256 -c SHA256SUMS
   ./Resources/IconComposer/verify_package.sh
   ./scripts/verify_release.sh
   ./scripts/audit_app_store.sh
   ```

2. 文件校验、图标包校验和工程回归必须通过。`audit_app_store.sh` 在填入正式 Bundle ID 并完成发布签名前会继续报告这两项阻断；不得静默忽略。
3. 阅读 `CURRENT_PRODUCT_BASELINE.md`，保持现有产品行为、视觉结构和交互闭环，不要重做产品或创建平行版本。

## 在 Xcode 中配置现有正式工程

1. 打开现有 `自在启动台.xcodeproj`，只使用其中的唯一 App Target，不得重建第二套工程。
2. App Store 首发版本已统一为 `1.0.0 (1)`；Bundle ID 必须由用户在自己的 Apple Developer 账号中注册并确认后替换 Xcode 中的本地占位标识。
3. `Sources/` 中全部 Swift 文件已属于唯一 App Target；`ZizaiLaunchpadApp.swift` 包含应用入口。
4. `Resources/AppIcon.icon` 已由 `Resources/IconComposer/01`–`04` 四个独立 SVG 生成并加入唯一 App Target；后续若调整图标，先阅读 `Resources/IconComposer/START_HERE.md` 并继续在同一文件中修改，不得新建平行主图标。
5. 最新 Xcode 使用 `AppIcon.icon` 时，不得再让 `Resources/Assets.xcassets/AppIcon.appiconset` 同时成为第二个主图标来源；原 Asset Catalog 只作为当前本地构建兼容资源保留。
6. 将 `Resources/PrivacyInfo.xcprivacy` 加入 Target Resources，并使用 `Resources/ZizaiLaunchpad.entitlements` 作为能力基线。
7. Deployment Target 保持当前工程的 macOS 13.0；如需调整，必须先完成编译、功能和视觉回归，不能只改数字。
8. 开启 App Sandbox。登录时后台准备继续使用 `SMAppService.mainApp`，保持默认关闭、用户主动开启、随时可关闭；登录启动使用 accessory 后台身份，不得弹出主窗口、占用程序坞或抢占焦点。
9. 使用开发者账号的最终 Team、Mac App Distribution 签名和 App Store provisioning profile。包内没有证书、描述文件、Apple ID、密码或本机临时签名应用。

## 包内能力与剩余 App Store 阻断

1. 包内包含唯一的 `自在启动台.xcodeproj`；必须在接手电脑重新执行 Release 门槛和未签名 Archive 结构验证，不能把打包电脑上的旧结果当作当前证据。正式签名 Archive 和 Validate App 仍需在最终标识与签名配置完成后执行。
2. `Resources/AppIcon.icon`、兼容图标资源和可复验的 Icon Composer 源材料都来自同一图标包；包内校验与当前构建必须重新验证其一致性。正式签名后的 Archive 仍需继续检查 Dock、Spotlight 与 App Store 归档预览。
3. Xcode Release 配置中的 Bundle ID 仍是本地占位符；必须替换为用户账号中注册的最终标识。`Resources/Info.plist` 会自动读取该设置，不应手工写死。
4. 本地脚本只用于产品回归，生成的是本地测试签名；它现在会生成与 Universal 2 二进制 UUID 匹配的 dSYM，但仍不能把 `scripts/build.sh` 的临时签名产物上传 App Store Connect。
5. `~/Applications/` 已改为用户在设置中明确选择文件夹，并通过只读安全范围书签持久授权；临时沙盒例外已移除。正式验收时需复测首次未授权、选择后扫描、重启恢复和移除授权四个状态。
6. 补齐公开的隐私政策 HTTPS 地址、支持页面、真实联系方式、SKU、价格、销售地区和审核联系人；候选商店截图已按 2880×1800、无 Alpha 生成，提交前确认最终选图与宣传文案。
7. 深浅色、降低动态效果、降低透明度和紧凑窗口已有自动渲染门槛；仍需在真实 macOS 13、Intel Mac 与 VoiceOver 下完成人工专项回归。

## 不允许做什么

- 不得导入任何旧 ZIP、旧 `.app`、旧 `build/`、旧验收记录或个人布局数据。
- 不得把本地测试构建当成 App Store Archive。
- 不得为了清除审核阻断而删除核心扫描、拖放、搜索、多实例识别或登录启动开关。
- 不得创建第二套源码目录、第二个产品版本或两个互相冲突的 Xcode Target。
- 未经用户明确确认，不得提交审核、自动发布、填写账号密码或替用户决定最终 Bundle ID、价格和销售地区。

## 完成标准

只有以下全部成立，才可向用户报告“已具备提交条件”：

- 当前产品基线测试通过，真实 Xcode 构建运行后的核心体验没有回归。
- 同一软件的多个安装实例都能独立扫描、显示和搜索。
- 顶部只有三组悬浮控件，没有整行白色或深色蒙层。
- 登录项默认关闭，开启和关闭都在真实系统中验证；退出登录或重启后确认无窗口、无焦点抢占，用户点击后即时恢复。
- `AppIcon.icon` 已成为唯一主图标来源，四个独立图层在 macOS 各外观和小尺寸下均经过真实系统验收。
- Xcode Archive 成功，Validate App 通过，正式签名、沙盒、隐私清单和版本号一致。
- App Store Connect 所需资料已补齐；任何仍需用户账号或业务决定的项目被明确列出。

完成 Archive 和 Validate 后，可以在用户已登录并明确授权的前提下上传构建；提交审核与发布仍需再次向用户确认。
