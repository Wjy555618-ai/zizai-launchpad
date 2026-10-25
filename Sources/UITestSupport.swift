import Foundation

/// Stable semantic identifiers shared by the production accessibility tree and
/// the end-to-end test suite. These identifiers describe product meaning, not
/// view hierarchy or coordinates, so UI tests remain valid when layout changes.
enum ZizaiAccessibilityID {
    static let brandCapsule = "brand.capsule"
    static let searchButton = "search.open"
    static let searchField = "search.field"
    static let searchResultsHeading = "search.results.heading"
    static let newGroupButton = "group.new"
    static let helpButton = "help.open"
    static let helpHeading = "help.heading"
    static let groupEditorHeading = "group-editor.heading"
    static let groupEditorNameField = "group-editor.name"
    static let groupsScreen = "screen.groups"
    static let spaceScreen = "screen.space"
    static let allAppsScreen = "screen.all-apps"
    static let canvasZoomOut = "canvas.zoom-out"
    static let canvasZoomValue = "canvas.zoom-value"
    static let canvasZoomIn = "canvas.zoom-in"
    static let canvasFit = "canvas.fit"
    static let toastUndo = "toast.undo"

    static func layoutMode(_ mode: LayoutMode) -> String {
        "navigation.\(modeIdentifier(mode))"
    }

    static func groupCard(_ groupID: String) -> String {
        "group.card.\(groupID)"
    }

    static func groupMenu(_ groupID: String) -> String {
        "group.menu.\(groupID)"
    }

    static func groupDragHandle(_ groupID: String) -> String {
        "group.drag-handle.\(groupID)"
    }

    static func appTile(_ appID: String) -> String {
        "app.tile.\(appID)"
    }

    private static func modeIdentifier(_ mode: LayoutMode) -> String {
        switch mode {
        case .groups: return "groups"
        case .space: return "space"
        case .allApps: return "all-apps"
        }
    }
}

/// Keeps production, unit-test-host and end-to-end launches on explicit,
/// non-overlapping paths. Unit tests need the application executable as their
/// bundle loader, but must not start the product's scanning and presentation
/// lifecycle before XCTest attaches. UI tests still launch the complete product
/// with deterministic local data and isolated persistence.
enum ZizaiLaunchMode: Equatable {
    case production
    case unitTestHost
    case uiTesting
}

struct ZizaiLaunchConfiguration {
    static let uiTestingEnvironmentKey = "ZIZAI_UI_TESTING"
    static let uiTestSessionEnvironmentKey = "ZIZAI_UI_TEST_SESSION"
    static let uiTestResetEnvironmentKey = "ZIZAI_UI_TEST_RESET"

    private static let xctestBundlePathEnvironmentKey = "XCTestBundlePath"
    private static let xctestInjectionTargetEnvironmentKey = "XCInjectBundleInto"

    let mode: ZizaiLaunchMode
    let stateDirectory: URL?
    let applications: [AppInfo]?

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ZizaiLaunchConfiguration {
        switch launchMode(environment: environment) {
        case .unitTestHost:
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "自在启动台-XCTestHost-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true
                )
            return ZizaiLaunchConfiguration(
                mode: .unitTestHost,
                stateDirectory: directory,
                applications: []
            )
        case .uiTesting:
            let session = sanitizedSession(
                environment[uiTestSessionEnvironmentKey] ?? UUID().uuidString
            )
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("自在启动台-UI测试", isDirectory: true)
                .appendingPathComponent(session, isDirectory: true)
            pruneTestStateDirectories(keeping: directory)
            prepareStateDirectory(
                directory,
                reset: environment[uiTestResetEnvironmentKey] != "0"
            )
            return ZizaiLaunchConfiguration(
                mode: .uiTesting,
                stateDirectory: directory,
                applications: fixtureApplications
            )
        case .production:
            return ZizaiLaunchConfiguration(
                mode: .production,
                stateDirectory: nil,
                applications: nil
            )
        }
    }

    /// UI testing takes precedence if Xcode propagates both test-action and
    /// app-launch environments. The explicit UI marker is the stronger
    /// contract: it must always launch the complete product surface.
    static func launchMode(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ZizaiLaunchMode {
        #if DEBUG
            if environment[uiTestingEnvironmentKey] == "1" {
                return .uiTesting
            }
            if isApplicationHostedUnitTest(environment: environment) {
                return .unitTestHost
            }
        #endif
        return .production
    }

    /// Application-hosted XCTest launches inject the test bundle into the app
    /// executable. These keys are part of Xcode's own process contract and are
    /// present before SwiftUI constructs the App. An XCUITest-controlled app is
    /// not a bundle loader and therefore does not expose either key.
    private static func isApplicationHostedUnitTest(
        environment: [String: String]
    ) -> Bool {
        guard
            let bundlePath = environment[xctestBundlePathEnvironmentKey],
            !bundlePath.isEmpty,
            let injectionTarget = environment[xctestInjectionTargetEnvironmentKey],
            !injectionTarget.isEmpty
        else { return false }
        return true
    }

    private static func prepareStateDirectory(_ directory: URL, reset: Bool) {
        do {
            if reset, FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let stateURL = directory.appendingPathComponent("布局.json")
            guard !FileManager.default.fileExists(atPath: stateURL.path) else { return }
            var initialState = PersistedState()
            initialState.hasSeenWelcome = true
            initialState.layoutMode = .groups
            try JSONEncoder().encode(initialState).write(to: stateURL, options: .atomic)
        } catch {
            fatalError("无法准备隔离的 UI 测试状态：\(error.localizedDescription)")
        }
    }

    private static func pruneTestStateDirectories(keeping currentDirectory: URL) {
        let root = currentDirectory.deletingLastPathComponent()
        guard
            let candidates = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
        else { return }

        for candidate in candidates where candidate != currentDirectory {
            try? FileManager.default.removeItem(at: candidate)
        }
    }

    private static func sanitizedSession(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(result.prefix(100))
    }

    /// Shared deterministic catalog for UI automation and in-process view
    /// composition tests. Keeping one fixture source prevents the two visual
    /// test layers from drifting into different products.
    static var fixtureApplications: [AppInfo] {
        [
            fixture(
                bundleIdentifier: "com.figma.Desktop",
                name: "Figma",
                chineseName: "Figma",
                path: "/Applications/Figma.app",
                purpose: "界面设计",
                group: .aiCreative
            ),
            fixture(
                bundleIdentifier: "com.figma.Desktop",
                name: "Figma",
                chineseName: "Figma",
                path: "/Applications/Figma+EX.app",
                purpose: "界面设计",
                group: .aiCreative
            ),
            fixture(
                bundleIdentifier: "com.tencent.xinWeChat",
                name: "WeChat",
                chineseName: "微信",
                path: "/Applications/WeChat.app",
                purpose: "即时沟通",
                group: .communication
            ),
            fixture(
                bundleIdentifier: "com.apple.Preview",
                name: "Preview",
                chineseName: "预览",
                path: "/System/Applications/Preview.app",
                purpose: "查看图片与 PDF",
                group: .productivity
            ),
            fixture(
                bundleIdentifier: "com.apple.Music",
                name: "Music",
                chineseName: "音乐",
                path: "/System/Applications/Music.app",
                purpose: "音乐播放",
                group: .entertainment
            ),
            fixture(
                bundleIdentifier: "com.apple.ActivityMonitor",
                name: "Activity Monitor",
                chineseName: "活动监视器",
                path: "/System/Applications/Utilities/Activity Monitor.app",
                purpose: "系统监控",
                group: .utilities
            ),
            fixture(
                bundleIdentifier: "com.apple.calculator",
                name: "Calculator",
                chineseName: "计算器",
                path: "/System/Applications/Calculator.app",
                purpose: "计算",
                group: .other
            ),
        ]
    }

    private static func fixture(
        bundleIdentifier: String,
        name: String,
        chineseName: String,
        path: String,
        purpose: String,
        group: AppGroup
    ) -> AppInfo {
        AppInfo(
            id: AppScanner.instanceIdentifier(
                bundleIdentifier: bundleIdentifier,
                path: path
            ),
            bundleIdentifier: bundleIdentifier,
            name: name,
            chineseName: chineseName,
            path: path,
            purpose: purpose,
            group: group
        )
    }
}
