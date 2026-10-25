# 架构说明

自在启动台是一个单 App Target、本地优先的 macOS 应用，另有独立 XCTest 与 XCUITest Target 承载 IDE/CI 可发现的回归验证。工程不依赖第三方 SDK，不使用服务端，也不上传应用列表或布局数据。

## 数据流

```text
AppScanner / ApplicationFolderAccess
                │
                ▼
    ApplicationCatalogLogic
      搜索文档 + 身份迁移
                │
                ▼
   ApplicationSearchPolicy
     分层匹配 + 噪声抑制
                │
                ▼
      LauncherStore 聚合根
   ┌────────┼────────┬────────┐
   ▼        ▼        ▼        ▼
Catalog   Library   Groups   Canvas
   └────────┴────┬───┴────────┘
                 ▼
     LauncherStateHistory
          PersistedStateIO
```

- `AppScanner` 只读扫描系统应用目录，以“Bundle ID + 规范化路径”识别安装实例，因此不会合并同一应用的多个安装版本。
- `ApplicationFolderAccess` 管理用户主动授予的 app-scoped 只读安全范围书签，授权仅在扫描期间激活并成对释放；源码能力、entitlement 与签名产物由同一安全能力契约校验。
- `ApplicationCatalogLogic` 生成分离的“可见词”与“技术身份词”，并承担旧身份迁移；`ApplicationSearchPolicy` 统一定义精确、前缀、连续片段和容错层级，技术词不参与子序列模糊匹配。
- `LauncherStore` 是 `@MainActor` 上唯一的可观察状态聚合根，只拥有生命周期、发布状态、统一提交、公告与持久化节奏；`LauncherStore+Catalog`、`LauncherStore+Library`、`LauncherStore+Groups`、`LauncherStore+Canvas` 分别承载目录查询、应用放置、分组生命周期和画布导航命令，不拥有平行状态。
- 所有可撤销命令都通过 `commitStateMutation` 原子提交完整 `PersistedState`，并由限长、值语义的 `LauncherStateHistory` 保存先前修订；不再把捕获 Store 与视图对象的闭包当作历史记录。
- 搜索匹配、扫描状态对账与几何修复、持久化 I/O 和空间几何算法分别收敛在 `ApplicationSearchPolicy`、`LauncherStateReconciler`、`StatePersistence` 和无状态 `SpatialLayoutEngine` 中，不在 Store 门面或各命令模块内维护平行实现。
- `StatePersistenceWriter` 通过串行 utility 队列在主线程之外保存布局，以 revision 防止旧写入覆盖新状态。
- `PersistedStateIO` 先校验当前数据，再更新备份，最后原子替换主文件。

## 界面与交互

- `RootView` 维持三个主视图的持久 `NSHostingView`，Tab 切换只更新轻量容器，避免重建整个应用网格。宿主层在原生窗口外观变化时统一同步 `effectiveAppearance` 并重新求值 SwiftUI 语义色，不由页面或单个文字各自管理深浅色分支。
- `SearchViews` 独立承担搜索控件与结果组合；`AllAppsViews` 独立承担完整应用目录、筛选与显隐事务；`LibraryViews` 只保留分组视图及其交互。多实例应用在通用图标项和搜索结果中都分行展示主名称与去除 `.app` 扩展名的实例来源，不把身份信息挤进窄小的单行标签。
- 品牌身份分为两个明确边界：`AppIcon.icon` 仅供 Finder、Dock、Spotlight 与 App Store 使用；界面内统一使用 `ZizaiBrandMark`，只渲染紧凑裁切的透明四色前景，在浅色与深色外观中均不添加底面、材质、描边或阴影。
- `InteractionGeometry` 负责输入手势与视口的纯计算；`SpatialLayoutEngine` 负责分组帧、应用网格、碰撞、尺寸映射与分组分离。指针操作、键盘/VoiceOver 自定义操作、迁移修复和测试共用这一套规则。
- 空间视图在拖动期间只更新局部预览，释放时才执行完整碰撞解析和持久化。
- 说明气泡使用不抢占焦点的顶层子窗口，不依赖列表、滚动区或卡片的局部层级；搜索或弹窗接管交互时会统一暂停、关闭并拒绝过期的异步气泡请求。
- `Compatibility` 统一处理深浅色、降低动态效果、降低透明度及系统版本差异；视觉门槛除了分别渲染深浅外观，还会在同一持久窗口中执行深色到浅色切换，检查三个主页文字和底部控件的语义对比度。

## 并发边界

- UI 状态始终留在主 Actor，避免 SwiftUI 发布跨线程状态。
- 文件扫描通过可取消的 worker task 执行。
- 图标预热分批让出执行权，避免首帧一次性解码全部应用图标。
- 布局写入由独立串行队列保序；应用退出时才执行同步刷盘。

## 安全与隐私

- App Sandbox 默认开启。
- 额外应用目录只申请用户选择的只读权限，并使用 app-scoped security bookmark 跨重启恢复；不使用临时沙盒例外。
- 应用不联网，不包含第三方追踪 SDK，不读取文稿、照片、通讯录或其他个人内容。
- 登录项由用户主动开启，使用 `SMAppService.mainApp`，不安装额外 helper。

## 验证策略

`Tests/XCTest/` 是标准 Xcode 测试 Target，用于快速、可定位、可在 CI 中直接产生 `.xcresult` 的原生回归。它覆盖应用身份与搜索语义、真实 Store 多实例与跨组操作、画布安全区和缩放、空间碰撞与无障碍等价事务、换序完整性、登录项状态、气泡生命周期、异步持久化顺序与备份。该 Target 明确串行执行：macOS App 宿主与全局 AppKit 生命周期不能被多个测试进程安全争用，确定性优先于几秒钟的并发收益。主视图和关键 sheet 的 SwiftUI/AppKit 组合统一由独立视觉渲染程序在深浅色下执行，并由 XCUITest 验证真实用户路径；应用宿主 XCTest 不再创建窗口来冒充视觉或端到端验收。

三种进程启动模式由 `ZizaiLaunchConfiguration` 集中判定，不在视图层分叉：生产启动执行完整扫描和窗口生命周期；XCTest 宿主使用空目录和隔离持久化，不激活产品展示；XCUITest 则使用确定性 fixture 与独立会话目录启动完整用户界面。三者共用稳定的 `WindowGroup` 根结构，避免测试隔离改变 SwiftUI 窗口身份或破坏 AppKit 状态恢复。

`Tests/XCUITests/` 属于独立的 `自在启动台-UI` 方案，覆盖三主视图与帮助弹窗、搜索多实例与两种外点收起、真实指针分组换序、真实指针跨组移动应用、空间内拖动应用及相应撤销、菜单跨组移动、应用显隐、画布缩放，以及分组新建、外点收起和重启持久化。启动就绪要求初始导航真实可点击且对应页面语义锚点已出现；切换完成同时核对目标页面和导航选中态，不依赖坐标、固定延时或单一控件的暂态状态。拖拽视图把实时几何写入不触发视图刷新的观察缓存，拖拽开始时再一次性冻结完整值快照；这既避免惰性容器逐项状态回写丢失落点，也切断“测量—刷新—再次测量”的 Preference 布局反馈环。独立交互审计再覆盖边界几何、状态事务与性能。主方案不会包含 UI Runner；`scripts/verify_release.sh`、`scripts/run_ui_tests.sh` 与 CI 都会使用全新 DerivedData 和隔离状态真实执行。Runner 建立连接失败、测试失败、跳过或非允许运行时警告都会保留 `.xcresult` 并判定失败，不得降级成通过。测试数量与结果由当前源码和当次 `.xcresult` 自动核对，不在稳定文档中手工维护。

`Tests/` 其余文件是可独立编译的行为与性能审计程序，覆盖：

- 搜索、换序、跨组拖放、碰撞修复、撤销和数据迁移。
- 同 Bundle ID 多实例扫描与缺失授权时的数据保护。
- Tab 切换、首帧准备、主线程响应、画布拖动的性能预算。
- Universal 2、macOS 13 部署目标、深浅色和辅助功能渲染。

`scripts/verify_release.sh` 是本地和远程共用的单一发布门槛：它会重新构建、运行 Xcode 静态分析和 XCTest、报告含声明式 UI 的单元测试整体行覆盖率，同时强制核心行为加权覆盖率和每个高风险模块下限；随后真实运行带代码覆盖率的 XCUITest，以 70% 应用整体下限和各关键 SwiftUI/AppKit 交互模块下限约束用户路径，再执行上述审计。它不会用旧的 `.artifacts.noindex/` 产物代替验证。SwiftUI `body` 是否在单元测试里被实例化不作为业务逻辑成熟度指标，声明式界面必须同时通过 XCUITest 覆盖率、深浅色视觉渲染和端到端断言。行为、视觉、安全与持久化分别由可执行测试证明；`verify_architecture_boundaries.py` 只检查模块所有权、依赖方向和复杂度上限，`verify_saved_layout.py` 只验证本机持久布局的几何不变量，不再以源码字符串和函数切片冒充产品验收。

应用 Target 支持 macOS 13。当前 Xcode 27 随附的 XCTest 运行库最低面向 macOS 14，因此 XCTest Target 使用 macOS 14；macOS 13 的编译边界由 Release 构建和独立审计程序验证，真实 macOS 13 运行仍属于发布前硬件验收。

共享的 `LaunchpadUITests.xctestplan` 只对 XCTest Runner 关闭 Thread Performance Checker。Xcode 27 会在 Runner 等待首个含 TextField 的 SwiftUI sheet 进入可访问性树时，把 XCTest 内部线程等待误报为应用 QoS 倒置。应用本身的主线程、异步扫描、标签切换、空间交互和长帧预算由独立性能审计覆盖；发布门槛仍拒绝 xcresult 中的任何运行时警告。

Xcode 27 默认为 Swift Target 规划 App Intents 元数据提取任务，即使产品完全没有 App Intents 依赖。本项目在项目级设置 `LM_SKIP_METADATA_EXTRACTION`，从任务规划阶段取消无意义的提取，而不是执行后过滤警告。发布门槛同时禁止产品源码引入 `AppIntents`；未来如需该能力，必须先移除跳过设置并恢复元数据验证。其余 Xcode 构建、XCTest 与 XCUITest 日志中的任何 `warning:` 都会直接阻断发布。
