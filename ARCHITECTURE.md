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

ApplicationRemovalPolicy
          │
          ▼
ApplicationRemovalCoordinator
   authorization + running check
          │
          ▼
   FileManager.moveItem
   to source-volume user Trash
```

- `AppScanner` 只读扫描系统应用目录，以“Bundle ID + 规范化路径”识别安装实例，因此不会合并同一应用的多个安装版本。
- `ApplicationFolderAccess` 分开管理两种 app-scoped 安全范围书签：额外目录扫描始终使用只读书签；应用管理使用单独的读写书签。`ApplicationRemovalAuthorizationScope` 把 `/Applications`、`~/Applications` 和外部直接容器定义为唯一授权边界：同一边界下的应用复用一份书签，而安全范围访问只在一次已确认的系统回收操作期间激活和成对释放。
- `ApplicationRemovalServices` 隔离系统路径保护、运行状态检测、App Management 权限拒绝分类、系统设置跳转与废纸篓移动。它通过 `.trashDirectory` 定位源磁盘对应的用户废纸篓，再在已激活安全范围的本进程内用 `moveItem` 直接移动；不再使用会把 `.app` 操作转交 `CategoriesService.xpc` 并丢失当前 App Management 授权主体的 `trashItem`。同名目标会生成唯一名称，只有原路径已消失且废纸篓目标已存在时才报告成功。`ApplicationRemovalOpenPanelPresenter` 把原生 `NSOpenPanel` 直接定位到预期授权边界，当前文件夹即为选择结果，用户无需选中 `.app`。`ApplicationRemovalCoordinator` 以 `idle / presenting / selectingAuthorization / awaitingAppManagementPermission / recycling` 单一状态机统一管理长按会话、两层系统授权、确认、返回自动重试和结果反馈；返回后只自动重试一次，同类失败会进入带错误域/代码的终态，绝不重新打开授权循环。
- `ApplicationManagementJiggleIcon` 把管理模式持续抖动局限在图标的 Core Animation 合成层；SwiftUI 只处理有限次的进入与退出包络，因此持续视觉反馈不再造成整个应用网格逐帧求值和布局。
- `ApplicationCatalogLogic` 生成分离的“可见词”与“技术身份词”，并承担旧身份迁移；`ApplicationSearchPolicy` 统一定义精确、前缀、连续片段和容错层级，技术词不参与子序列模糊匹配。
- `LauncherStore` 是 `@MainActor` 上唯一的可观察状态聚合根，只拥有生命周期、发布状态、统一提交、公告与持久化节奏；`LauncherStore+Catalog`、`LauncherStore+Library`、`LauncherStore+Groups`、`LauncherStore+Canvas` 分别承载目录查询、应用放置、分组生命周期和画布导航命令，不拥有平行状态。
- 所有可撤销命令都通过 `commitStateMutation` 原子提交完整 `PersistedState`，并由限长、值语义的 `LauncherStateHistory` 保存先前修订；不再把捕获 Store 与视图对象的闭包当作历史记录。
- 搜索匹配、扫描状态对账与几何修复、持久化 I/O 和空间几何算法分别收敛在 `ApplicationSearchPolicy`、`LauncherStateReconciler`、`StatePersistence` 和无状态 `SpatialLayoutEngine` 中，不在 Store 门面或各命令模块内维护平行实现。
- `StatePersistenceWriter` 通过串行 utility 队列在主线程之外保存布局，以 revision 防止旧写入覆盖新状态。
- `PersistedStateIO` 先校验当前数据，再更新备份，最后原子替换主文件。

## 界面与交互

- `RootView` 只组合顶层导航和主内容；`PrimaryLayerHosting` 维持三个主视图的持久 `NSHostingView`，Tab 切换只更新轻量容器，避免重建整个应用网格。宿主层在原生窗口外观变化时统一同步 `effectiveAppearance` 并重新求值 SwiftUI 语义色，不由页面或单个文字各自管理深浅色分支。`TopChromeViews` 只负责顶部导航，`AppPresentationViews` 只负责通用应用图标与状态呈现。
- `SearchViews` 独立承担搜索控件与结果组合；`AllAppsViews` 独立承担完整应用目录、筛选与显隐事务。分组和空间页面均按页面组合、分组容器、应用项与辅助控件拆分，跨文件只暴露组合所需的内部边界。多实例应用在通用图标项和搜索结果中都分行展示主名称与去除 `.app` 扩展名的实例来源，不把身份信息挤进窄小的单行标签。
- 品牌身份分为两个明确边界：`AppIcon.icon` 仅供 Finder、Dock、Spotlight 与 App Store 使用；界面内统一使用 `ZizaiBrandMark`，只渲染紧凑裁切的透明四色前景，在浅色与深色外观中均不添加底面、材质、描边或阴影。
- `InteractionGeometry` 负责输入手势与视口的纯计算；`SpatialLayoutEngine` 负责分组帧、应用网格、碰撞、尺寸映射与分组分离。指针操作、键盘/VoiceOver 自定义操作、迁移修复和测试共用这一套规则。
- 空间视图的平移与缩放共用 `CanvasViewportInteractionSession`：世界层在不变基线上渲染，指针频率只更新外层合成变换，`CanvasEventView` 按当前屏幕刷新率合并滚轮和捏合输入，交互结束后向 `LauncherStore` 发布并保存一次。分组移动、尺寸调整和应用移动在拖动期间只更新局部预览，释放时才执行完整碰撞解析和持久化。图书馆拖动冻结观察几何，插入标记只更新渲染外观而不改变 `LazyVStack` 布局尺寸。
- 说明气泡使用不抢占焦点的顶层子窗口，不依赖列表、滚动区或卡片的局部层级。`AppTooltipPanelController` 是渐显、渐隐、导航作废和锚点移动抑制的唯一生命周期所有者；窗口滚动或锚点布局一变化就先渐隐并解绑，直到指针离开原锚点才允许再次展示。搜索或弹窗接管交互时同样走这条统一的作废路径。
- `Compatibility` 统一处理深浅色、降低动态效果、降低透明度及系统版本差异；视觉门槛除了分别渲染深浅外观，还会在同一持久窗口中执行深色到浅色切换，检查三个主页文字和底部控件的语义对比度。
- 四种应用呈现（分组、空间、全部应用和搜索）共用 `ApplicationManagementViews`；`ApplicationManagementMotion` 只驱动有限的进入与退出过渡，稳定阶段不运行逐图标时间线或无限动画，避免真实应用目录密度下持续触发布局并饿死模态按钮的鼠标事件。`ApplicationManagementLifecycle` 统一处理空白点击、超时、导航、窗口和应用焦点边界；`ApplicationManagementChrome` 通过真实图标的 Anchor Preference 将白色删除控件定位在左上角，不依赖分组、卡片或画布的经验偏移。系统保护应用不显示删除控件；运行中拦截和第三方应用确认不会在各页面复制实现。

## 并发边界

- UI 状态始终留在主 Actor，避免 SwiftUI 发布跨线程状态。
- 文件扫描通过可取消的 worker task 执行。
- 图标预热分批让出执行权，避免首帧一次性解码全部应用图标。
- 布局写入由独立串行队列保序；应用退出时才执行同步刷盘。

## 安全与隐私

- App Sandbox 默认开启。
- entitlement 使用标准的用户选择读写能力，不使用临时沙盒例外；额外目录的扫描书签仍显式带有只读限制，管理书签则只在用户确认移动应用时短暂启用。
- 应用移除不提权、不强制结束进程、不直接永久删除，也不扫描或清理应用支持文件；系统应用和自在启动台自身在策略层直接阻断。
- 应用不联网，不包含第三方追踪 SDK，不读取文稿、照片、通讯录或其他个人内容。
- 登录项由用户主动开启，使用 `SMAppService.mainApp`，不安装额外 helper。

## 验证策略

`Tests/XCTest/` 是标准 Xcode 测试 Target，用于快速、可定位、可在 CI 中直接产生 `.xcresult` 的原生回归。它覆盖应用身份与搜索语义、真实 Store 多实例与跨组操作、画布安全区和缩放、空间碰撞与无障碍等价事务、换序完整性、登录项状态、气泡生命周期、异步持久化顺序与备份。该 Target 明确串行执行：macOS App 宿主与全局 AppKit 生命周期不能被多个测试进程安全争用，确定性优先于几秒钟的并发收益。主视图和关键 sheet 的 SwiftUI/AppKit 组合统一由独立视觉渲染程序在深浅色下执行，并由 XCUITest 验证真实用户路径；应用宿主 XCTest 不再创建窗口来冒充视觉或端到端验收。

三种进程启动模式由 `ZizaiLaunchConfiguration` 集中判定，不在视图层分叉：生产启动执行完整扫描和窗口生命周期；XCTest 宿主使用空目录和隔离持久化，不激活产品展示；XCUITest 则使用确定性 fixture 与独立会话目录启动完整用户界面。三者共用稳定的 `WindowGroup` 根结构，避免测试隔离改变 SwiftUI 窗口身份或破坏 AppKit 状态恢复。

`Tests/XCUITests/` 属于独立的 `自在启动台-UI` 方案，覆盖三主视图与帮助弹窗、搜索多实例与两种外点收起、真实指针分组换序、真实指针跨组移动应用、空间内拖动应用及相应撤销、菜单跨组移动、应用显隐、画布缩放，以及分组新建、外点收起和重启持久化。启动就绪要求初始导航真实可点击且对应页面语义锚点已出现；切换完成同时核对目标页面和导航选中态，不依赖坐标、固定延时或单一控件的暂态状态。拖拽视图把实时几何写入不触发视图刷新的观察缓存，拖拽开始时再一次性冻结完整值快照；这既避免惰性容器逐项状态回写丢失落点，也切断“测量—刷新—再次测量”的 Preference 布局反馈环。独立交互审计再覆盖边界几何、状态事务与性能。主方案不会包含 UI Runner；默认 `scripts/verify_release.sh` 与 `scripts/run_ui_tests.sh` 会在已授权交互式桌面使用全新 DerivedData 和隔离状态真实执行。Runner 建立连接失败、测试失败、跳过或非允许运行时警告都会保留 `.xcresult` 并判定失败，不得降级成通过。GitHub 托管工作流并行执行 `--hosted-ci-core` 与 `--hosted-ci-runtime`，完整编译同一 UI 套件并执行其他确定性门槛，但不会产生 XCUITest 通过结论或完整质量证据；这是对执行环境权限边界的显式建模，不是对端到端标准的替代。测试数量与结果由当前源码和当次 `.xcresult` 自动核对，不在稳定文档中手工维护。

`Tests/` 其余文件是可独立编译的行为与性能审计程序，覆盖：

- 搜索、换序、跨组拖放、碰撞修复、撤销和数据迁移。
- 同 Bundle ID 多实例扫描与缺失授权时的数据保护。
- Tab 切换、首帧准备、主线程响应、画布拖动的性能预算。
- Universal 2、macOS 13 部署目标、深浅色和辅助功能渲染。

页面切换性能同时记录 wall-clock 与当前主线程 CPU 时间：持续 P95/P99 约束用户可见帧预算，单次绝对门槛约束产品自身 CPU 工作量。共享 CI 主机或 WindowServer 的偶发抢占会保留在 wall 最大值诊断中，但不会被伪装成应用代码突然执行了等量工作。

`scripts/verify_release.sh` 是本地与远程共享实现、按能力和职责显式配置的发布门槛。默认交互式配置会依次执行 core 与 runtime 阶段，并在生成质量证据前直接编排公开仓库候选审计。远程工作流把同一实现拆成 `--hosted-ci-core` 与 `--hosted-ci-runtime` 并行矩阵，公开仓库审计只由 core 阶段执行一次。四项 SwiftUI 运行时审计通过内容摘要绑定的单一 `-whole-module-optimization` 产物复用完整产品源图，构建耗时显式可观测。视觉证据固定为 2×、8 位 RGB 离屏画布，商店四场景必须连续两轮产生逐字节一致的 PNG 与 JPEG。托管 core 会构建完整 UI 套件，但不会在缺少受信任交互式辅助功能会话的主机上伪造 XCUITest 执行结果。

行为、视觉、安全与持久化分别由可执行测试证明。`verify_architecture_boundaries.py` 只检查模块所有权、依赖方向和复杂度上限。`verify_saved_layout.py` 只验证调用者显式指定的持久布局几何不变量；缺失文件或冲突数据均失败关闭，不再以跳过、源码字符串或函数切片冒充产品验收。

应用 Target 支持 macOS 13。当前 Xcode 27 随附的 XCTest 运行库最低面向 macOS 14，因此 XCTest Target 使用 macOS 14；macOS 13 的编译边界由 Release 构建和独立审计程序验证，真实 macOS 13 运行仍属于发布前硬件验收。

共享的 `LaunchpadUITests.xctestplan` 只对 XCTest Runner 关闭 Thread Performance Checker。Xcode 27 会在 Runner 等待首个含 TextField 的 SwiftUI sheet 进入可访问性树时，把 XCTest 内部线程等待误报为应用 QoS 倒置。应用本身的主线程、异步扫描、标签切换、空间交互和长帧预算由独立性能审计覆盖；发布门槛仍拒绝 xcresult 中的任何运行时警告。

Xcode 27 默认为 Swift Target 规划 App Intents 元数据提取任务，即使产品完全没有 App Intents 依赖。本项目在项目级设置 `LM_SKIP_METADATA_EXTRACTION`，从任务规划阶段取消无意义的提取，而不是执行后过滤警告。发布门槛同时禁止产品源码引入 `AppIntents`；未来如需该能力，必须先移除跳过设置并恢复元数据验证。其余 Xcode 构建、XCTest 与 XCUITest 日志中的任何 `warning:` 都会直接阻断发布。
