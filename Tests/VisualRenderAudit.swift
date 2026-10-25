import AppKit
import SwiftUI

@main
@MainActor
enum VisualRenderAudit {
    static func main() {
        let output =
            CommandLine.arguments.dropFirst().first
            ?? "/tmp/zizai-visual-audit.png"
        let layoutArgument = CommandLine.arguments.dropFirst(2).first ?? "space"
        let appearanceArgument = CommandLine.arguments.dropFirst(3).first ?? "dark"
        let auditColorScheme: ColorScheme = appearanceArgument == "light" ? .light : .dark
        let auditAppearance = NSAppearance(
            named: appearanceArgument == "light" ? .aqua : .darkAqua
        )
        let layoutMode: LayoutMode
        switch layoutArgument {
        case "groups", "appearanceTransitionGroups", "storeGroups":
            layoutMode = .groups
        case "allApps", "appearanceTransitionAllApps", "storeAllApps":
            layoutMode = .allApps
        case "appearanceTransitionSpace", "compactSpace", "compactWindow", "overviewSpace", "search",
            "storeSearch", "storeSpace":
            layoutMode = .space
        default:
            layoutMode = .space
        }
        guard let iconPath = ProcessInfo.processInfo.environment["ZIZAI_ICON_PATH"],
            let appIcon = NSImage(contentsOfFile: iconPath)
        else {
            fail("无法载入当前应用图标")
        }
        NSApplication.shared.applicationIconImage = appIcon

        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-visual-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let fixtureApplications = visualFixtureApplications()
        let store = LauncherStore(
            stateDirectory: stateDirectory,
            appProvider: { fixtureApplications }
        )
        store.state.hasSeenWelcome = true
        store.state.layoutMode = layoutMode
        if layoutArgument == "storeGroups" {
            let visibleGroupIDs = Set([
                AppGroup.aiCreative.stableID,
                AppGroup.communication.stableID,
            ])
            store.state.userGroups.removeAll { !visibleGroupIDs.contains($0.id) }
        } else if layoutArgument == "storeSpace" {
            let visibleGroupIDs = Set([
                AppGroup.aiCreative.stableID,
                AppGroup.communication.stableID,
                AppGroup.productivity.stableID,
            ])
            store.state.userGroups.removeAll { !visibleGroupIDs.contains($0.id) }
            for group in store.groups {
                store.arrangeApps(in: group.id)
                store.fitGroupToContent(id: group.id)
            }
            store.toast = nil
            store.fitAllGroups(in: CGSize(width: 1_440, height: 844))
        } else if layoutArgument == "overviewSpace" {
            store.state.canvasScale = 0.34
            store.state.canvasOffsetX = 0
            store.state.canvasOffsetY = -40
        } else if layoutArgument == "compactSpace" {
            store.state.canvasScale = 0.72
            store.state.canvasOffsetX = 0
            store.state.canvasOffsetY = -40
        } else if layoutMode == .space {
            let focusedGroupID = AppGroup.communication.stableID
            store.selectedGroupID = focusedGroupID
            store.focus(on: focusedGroupID, in: CGSize(width: 1_360, height: 804))
        }

        let root: AnyView
        let canvasSize: CGSize
        if layoutArgument == "tooltipSpacing" {
            root = AnyView(
                AppTooltipSpacingAuditView()
                    .preferredColorScheme(auditColorScheme)
            )
            canvasSize = CGSize(width: 420, height: 420)
        } else if layoutArgument == "tooltip" {
            root = AnyView(
                TooltipVisualAuditView()
                    .preferredColorScheme(auditColorScheme)
            )
            canvasSize = CGSize(width: 900, height: 280)
        } else {
            let applicationRoot = RootView(
                layoutModeController: LayoutModeController(selection: layoutMode)
            )
            .environmentObject(store)
            if layoutArgument.hasPrefix("appearanceTransition") {
                root = AnyView(applicationRoot)
            } else {
                root = AnyView(applicationRoot.preferredColorScheme(auditColorScheme))
            }
            if layoutArgument.hasPrefix("store") {
                canvasSize = CGSize(width: 1_440, height: 900)
            } else if layoutArgument == "compactWindow" {
                canvasSize = CGSize(width: 1_040, height: 680)
            } else {
                canvasSize = CGSize(width: 1_360, height: 860)
            }
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: canvasSize)
        let initialAppearance =
            layoutArgument.hasPrefix("appearanceTransition")
            ? NSAppearance(named: .darkAqua)
            : auditAppearance
        hosting.appearance = initialAppearance

        let window = NSWindow(
            contentRect: hosting.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = initialAppearance
        window.contentView = hosting
        RootWindowMaterial.install(in: window)
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        if layoutArgument.hasPrefix("appearanceTransition") {
            let lightAppearance = NSAppearance(named: .aqua)
            window.appearance = lightAppearance
            hosting.appearance = lightAppearance
            hosting.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if layoutArgument == "search" || layoutArgument == "storeSearch" {
            store.searchText = "原型"
            store.requestFocusSearch()
        }
        validateStoreComposition(store, layoutArgument: layoutArgument)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard let captureView = window.contentView else {
            fail("无法获取根窗口材质")
        }
        captureView.displayIfNeeded()

        guard let bitmap = captureView.bitmapImageRepForCachingDisplay(in: captureView.bounds) else {
            fail("无法创建离屏界面画布")
        }
        captureView.cacheDisplay(in: captureView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            fail("无法编码界面快照")
        }
        do {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        } catch {
            fail("无法保存界面快照：\(error.localizedDescription)")
        }
        validateSnapshot(
            bitmap,
            canvasSize: canvasSize,
            layoutArgument: layoutArgument,
            appearanceArgument: appearanceArgument
        )
        print(output)
    }

    /// Store screenshots and visual audits use fictional applications with
    /// artwork generated by this project. This keeps rendering deterministic,
    /// avoids exposing a developer's installed applications, and removes
    /// third-party trademark/licensing ambiguity from release assets.
    private static func visualFixtureApplications() -> [AppInfo] {
        typealias FixtureDefinition = (name: String, symbol: String, purpose: String)
        let groups: [(AppGroup, [FixtureDefinition])] = [
            (
                .aiCreative,
                [
                    ("灵感笔记", "lightbulb.max.fill", "收集想法"),
                    ("创意画板", "paintpalette.fill", "视觉创作"),
                    ("影像剪辑", "scissors", "编辑视频"),
                    ("原型工坊", "square.on.square", "制作原型"),
                    ("色彩助手", "eyedropper.halffull", "管理色彩"),
                    ("字体实验", "textformat", "字体设计"),
                    ("动效台", "sparkles", "创作动效"),
                    ("图标盒", "app.dashed", "图标设计"),
                ]
            ),
            (
                .communication,
                [
                    ("消息", "message.fill", "即时沟通"),
                    ("会议", "video.fill", "团队会议"),
                    ("传送", "paperplane.fill", "文件协作"),
                    ("团队空间", "person.3.fill", "团队协作"),
                    ("邮件", "envelope.fill", "邮件往来"),
                    ("协作文档", "doc.badge.ellipsis", "共同编辑"),
                    ("通讯录", "person.crop.circle.fill", "联系人"),
                    ("白板", "rectangle.and.pencil.and.ellipsis", "团队白板"),
                ]
            ),
            (
                .productivity,
                [
                    ("专注", "checkmark.circle.fill", "专注任务"),
                    ("日程", "calendar", "管理时间"),
                    ("写作", "doc.text.fill", "文档写作"),
                    ("待办", "checklist", "任务清单"),
                    ("表格", "tablecells.fill", "数据表格"),
                    ("演示", "rectangle.on.rectangle.angled", "演示文稿"),
                    ("速记", "square.and.pencil", "快速记录"),
                    ("扫描", "doc.viewfinder", "文稿扫描"),
                ]
            ),
            (
                .entertainment,
                [
                    ("音乐室", "music.note", "音乐播放"),
                    ("播客台", "mic.fill", "播客节目"),
                    ("影院", "play.rectangle.fill", "视频播放"),
                    ("阅读", "books.vertical.fill", "阅读书籍"),
                    ("游戏", "gamecontroller.fill", "休闲游戏"),
                    ("电台", "radio.fill", "在线电台"),
                    ("相册", "photo.on.rectangle.angled", "浏览照片"),
                ]
            ),
            (
                .utilities,
                [
                    ("文件整理", "folder.fill", "管理文件"),
                    ("系统监控", "waveform.path.ecg", "查看状态"),
                    ("终端", "terminal.fill", "开发工具"),
                    ("密码库", "key.fill", "保管密码"),
                    ("设备中心", "macbook.and.iphone", "管理设备"),
                    ("网络工具", "network", "网络诊断"),
                    ("备份", "externaldrive.fill.badge.timemachine", "数据备份"),
                ]
            ),
            (
                .other,
                [
                    ("快捷收藏", "star.fill", "收藏内容"),
                    ("归档", "archivebox.fill", "整理资料"),
                    ("计算", "function", "快速计算"),
                    ("翻译", "character.book.closed.fill", "翻译文本"),
                    ("天气", "cloud.sun.fill", "查看天气"),
                    ("地图", "map.fill", "地点导航"),
                    ("词典", "text.book.closed.fill", "查找词义"),
                ]
            ),
        ]
        let palette = [
            Color(red: 0.35, green: 0.38, blue: 0.95),
            Color(red: 0.78, green: 0.30, blue: 0.82),
            Color(red: 0.96, green: 0.33, blue: 0.41),
            Color(red: 0.17, green: 0.72, blue: 0.49),
            Color(red: 0.15, green: 0.57, blue: 0.92),
            Color(red: 0.96, green: 0.62, blue: 0.18),
            Color(red: 0.26, green: 0.66, blue: 0.78),
            Color(red: 0.46, green: 0.50, blue: 0.58),
        ]
        let specifications = groups.flatMap { group, definitions in
            definitions.map { (group: group, definition: $0) }
        }

        var applications = specifications.enumerated().map { index, specification in
            let (name, symbol, purpose) = specification.definition
            let group = specification.group
            let path = "zizai-fixture://store-screenshot/\(name).app"
            IconCache.shared.registerFixtureIcon(
                visualFixtureIcon(symbol: symbol, color: palette[index % palette.count]),
                for: path
            )
            return AppInfo(
                id: "visual-fixture-\(index)",
                bundleIdentifier: "com.zizai.fixture.\(index)",
                name: name,
                chineseName: name,
                path: path,
                purpose: purpose,
                group: group
            )
        }
        if let prototype = applications.first(where: { $0.name == "原型工坊" }) {
            let previewPath = "zizai-fixture://store-screenshot/原型工坊预览版.app"
            IconCache.shared.registerFixtureIcon(
                visualFixtureIcon(
                    symbol: "square.stack.3d.up.fill",
                    color: Color(red: 0.38, green: 0.42, blue: 0.96)
                ),
                for: previewPath
            )
            applications.append(
                AppInfo(
                    id: "visual-fixture-prototype-preview",
                    bundleIdentifier: prototype.bundleIdentifier,
                    name: prototype.name,
                    chineseName: prototype.chineseName,
                    path: previewPath,
                    purpose: prototype.purpose,
                    group: prototype.group
                )
            )
        }
        return applications
    }

    private static func validateStoreComposition(
        _ store: LauncherStore,
        layoutArgument: String
    ) {
        switch layoutArgument {
        case "storeGroups":
            guard
                store.groups.map(\.id) == [
                    AppGroup.aiCreative.stableID,
                    AppGroup.communication.stableID,
                ]
            else {
                fail("商店分组截图必须展示两个完整分组，不能依赖视口裁切隐藏内容")
            }
        case "storeSpace":
            guard store.groups.count == 3,
                store.state.canvasScale >= 0.5,
                store.state.canvasScale <= 1
            else {
                fail("商店空间截图必须在可读缩放下完整展示三个分组")
            }
        case "storeSearch":
            let results = store.searchResults
            guard results.count == 2,
                results.allSatisfy({
                    guard let label = store.instanceLabel(for: $0) else { return false }
                    return !label.hasSuffix(".app") && !(label.first?.isNumber ?? false)
                })
            else {
                fail("商店搜索截图必须只展示两份可读、无工程痕迹的多实例结果")
            }
        case "storeAllApps":
            guard store.apps.count >= 40 else {
                fail("商店应用库截图缺少足以表达完整产品价值的示例内容")
            }
        default:
            break
        }
    }

    private static func visualFixtureIcon(symbol: String, color: Color) -> NSImage {
        let renderer = ImageRenderer(
            content:
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.78), color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: symbol)
                        .font(.system(size: 66, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                }
                .frame(width: 160, height: 160)
        )
        renderer.scale = 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: 160, height: 160))
    }

    /// A screenshot is useful evidence only when critical chrome has visible
    /// foreground/background separation. This catches the previous false
    /// positive where dark-mode labels rendered black on black while the audit
    /// merely checked that a PNG file existed.
    private static func validateSnapshot(
        _ bitmap: NSBitmapImageRep,
        canvasSize: CGSize,
        layoutArgument: String,
        appearanceArgument: String
    ) {
        var topRegions: [(String, CGRect)] = [
            ("品牌区", CGRect(x: 20, y: 4, width: 210, height: 76)),
            ("顶部操作区", CGRect(x: canvasSize.width - 190, y: 4, width: 180, height: 76)),
        ]
        if layoutArgument == "search" || layoutArgument == "storeSearch" {
            topRegions.append(
                ("搜索区", CGRect(x: canvasSize.width - 530, y: 4, width: 330, height: 76))
            )
        } else {
            topRegions.append(
                (
                    "视图切换区",
                    CGRect(x: canvasSize.width / 2 - 190, y: 4, width: 380, height: 76)
                )
            )
        }
        var regions = topRegions
        if layoutArgument == "space" || layoutArgument == "appearanceTransitionSpace"
            || layoutArgument == "compactWindow"
            || layoutArgument == "storeSpace"
        {
            regions.append(
                ("底部分组导航", CGRect(x: 12, y: canvasSize.height - 78, width: 560, height: 66))
            )
            regions.append(
                ("缩放控制区", CGRect(x: canvasSize.width - 220, y: canvasSize.height - 78, width: 208, height: 66))
            )
        }

        for (name, rect) in regions {
            let contrast = luminanceRange(inTopOriginRect: rect, bitmap: bitmap, canvasSize: canvasSize)
            guard contrast >= 0.22 else {
                fail("快照中“\(name)”对比度异常（亮度范围 \(String(format: "%.3f", contrast))）")
            }
        }

        let brandCapsuleLuminance = luminance(
            // Sample the surrounding capsule's padding, not the transparent
            // multicolor artwork. The in-app mark itself has no surface.
            atTopOriginPoint: CGPoint(x: 34, y: 28),
            bitmap: bitmap,
            canvasSize: canvasSize
        )
        if appearanceArgument == "dark" {
            guard brandCapsuleLuminance <= 0.42 else {
                fail(
                    "深色模式品牌胶囊仍为浅色底（亮度 \(String(format: "%.3f", brandCapsuleLuminance))）"
                )
            }
        } else {
            guard brandCapsuleLuminance >= 0.62 else {
                fail(
                    "浅色模式品牌胶囊未保持浅色底（亮度 \(String(format: "%.3f", brandCapsuleLuminance))）"
                )
            }
        }

        let expectsDarkInk = appearanceArgument == "light"
        let validateSemanticInk: (String, CGRect, CGFloat) -> Void = { name, rect, minimum in
            let ratio = pixelRatio(
                inTopOriginRect: rect,
                bitmap: bitmap,
                canvasSize: canvasSize,
                where: { luminance in
                    expectsDarkInk ? luminance <= 0.48 : luminance >= 0.72
                }
            )
            guard ratio >= minimum else {
                let expected = expectsDarkInk ? "深色" : "浅色"
                fail(
                    "\(name)没有使用\(expected)语义前景（有效像素占比 \(String(format: "%.3f", ratio))）"
                )
            }
        }

        switch layoutArgument {
        case "allApps", "appearanceTransitionAllApps", "storeAllApps":
            validateSemanticInk(
                "应用名称",
                CGRect(x: 64, y: 148, width: 116, height: 24),
                0.012
            )
        case "groups", "appearanceTransitionGroups", "storeGroups":
            validateSemanticInk(
                "分组标题",
                CGRect(x: 60, y: 115, width: 190, height: 50),
                0.012
            )
        case "space", "appearanceTransitionSpace", "compactWindow", "storeSpace":
            validateSemanticInk(
                "底部分组导航",
                CGRect(x: 10, y: canvasSize.height - 75, width: min(540, canvasSize.width - 20), height: 60),
                0.012
            )
            validateSemanticInk(
                "缩放控制区",
                CGRect(x: canvasSize.width - 200, y: canvasSize.height - 75, width: 185, height: 60),
                0.006
            )
        default:
            break
        }
    }

    private static func luminance(
        atTopOriginPoint point: CGPoint,
        bitmap: NSBitmapImageRep,
        canvasSize: CGSize
    ) -> CGFloat {
        let scaleX = CGFloat(bitmap.pixelsWide) / canvasSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / canvasSize.height
        let x = min(bitmap.pixelsWide - 1, max(0, Int(point.x * scaleX)))
        let y = min(bitmap.pixelsHigh - 1, max(0, Int(point.y * scaleY)))
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            fail("无法读取品牌标识像素")
        }
        return color.redComponent * 0.2126
            + color.greenComponent * 0.7152
            + color.blueComponent * 0.0722
    }

    private static func luminanceRange(
        inTopOriginRect rect: CGRect,
        bitmap: NSBitmapImageRep,
        canvasSize: CGSize
    ) -> CGFloat {
        let scaleX = CGFloat(bitmap.pixelsWide) / canvasSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / canvasSize.height
        let minX = max(0, Int(rect.minX * scaleX))
        let maxX = min(bitmap.pixelsWide - 1, Int(rect.maxX * scaleX))
        let minY = max(0, Int(rect.minY * scaleY))
        let maxY = min(bitmap.pixelsHigh - 1, Int(rect.maxY * scaleY))
        let strideX = max(1, (maxX - minX) / 120)
        let strideY = max(1, (maxY - minY) / 50)
        var darkest: CGFloat = 1
        var lightest: CGFloat = 0

        for y in Swift.stride(from: minY, through: maxY, by: strideY) {
            for x in Swift.stride(from: minX, through: maxX, by: strideX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let luminance =
                    color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                darkest = min(darkest, luminance)
                lightest = max(lightest, luminance)
            }
        }
        return lightest - darkest
    }

    private static func pixelRatio(
        inTopOriginRect rect: CGRect,
        bitmap: NSBitmapImageRep,
        canvasSize: CGSize,
        where predicate: (CGFloat) -> Bool
    ) -> CGFloat {
        let scaleX = CGFloat(bitmap.pixelsWide) / canvasSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / canvasSize.height
        let minX = max(0, Int(rect.minX * scaleX))
        let maxX = min(bitmap.pixelsWide - 1, Int(rect.maxX * scaleX))
        let minY = max(0, Int(rect.minY * scaleY))
        let maxY = min(bitmap.pixelsHigh - 1, Int(rect.maxY * scaleY))
        var matching = 0
        var sampled = 0

        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let luminance =
                    color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                sampled += 1
                if predicate(luminance) { matching += 1 }
            }
        }
        guard sampled > 0 else { return 0 }
        return CGFloat(matching) / CGFloat(sampled)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("视觉渲染验收失败：\(message)\n".utf8))
        exit(1)
    }
}

private struct AppTooltipSpacingAuditView: View {
    private let iconSize: CGFloat = 72

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 44) {
                auditApp(label: "上一行应用")

                VStack(spacing: 7) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: iconSize, height: iconSize)
                        .overlay(alignment: .bottom) {
                            AppTooltipAboveIcon(text: "笔记与文档", iconSize: iconSize)
                        }
                        .frame(width: iconSize, height: iconSize)

                    Text("目标应用")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
    }

    private func auditApp(label: String) -> some View {
        VStack(spacing: 7) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
            Text(label)
                .font(.system(size: 14, weight: .medium))
        }
    }
}

private struct TooltipVisualAuditView: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.pink.opacity(0.035))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.pink.opacity(0.18), lineWidth: 1)
                }
                .frame(width: 560, height: 150)

            HStack(alignment: .top, spacing: 72) {
                VStack(spacing: 8) {
                    DockStyleTooltip(text: "微信")
                    Text("微信")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }

                VStack(alignment: .leading, spacing: 8) {
                    DockStyleTooltip(
                        text: "11 个应用 · 视频、音乐、阅读与游戏",
                        tailX: 44
                    )
                    Text("影音娱乐")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .padding(.leading, 24)
                }

            }
        }
    }
}
