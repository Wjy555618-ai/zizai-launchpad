import AppKit
import Foundation

enum AppScanner {
    static func scan(additionalApplicationRoots: [URL] = []) -> [AppInfo] {
        var chosen: [String: AppInfo] = [:]
        for item in scanCandidates(additionalApplicationRoots: additionalApplicationRoots) {
            // Bundle identifiers describe an app family, not an installed instance.
            // Multiple real apps may intentionally share one identifier (for example,
            // release/beta builds or several installed versions). Only collapse paths
            // that resolve to the same application bundle.
            chosen[item.id] = item
        }

        return chosen.values.sorted {
            if $0.group != $1.group {
                return $0.group.sortIndex < $1.group.sortIndex
            }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    /// Keeps the pre-deduplication candidates available to the scanner audit so
    /// every app family on the current Mac is checked, not only named examples.
    static func scanCandidates(additionalApplicationRoots: [URL] = []) -> [AppInfo] {
        var roots: [(URL, Bool)] = [
            (URL(fileURLWithPath: "/Applications", isDirectory: true), true),
            (URL(fileURLWithPath: "/System/Applications", isDirectory: true), false),
            (URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true), false),
            (URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true), false),
        ]
        roots.append(contentsOf: additionalApplicationRoots.map { ($0, true) })

        var visitedRoots = Set<String>()

        var candidates: [URL] = []
        for (url, includeChildren) in roots {
            guard !Task.isCancelled else { return [] }
            let path = canonicalPath(for: url)
            guard visitedRoots.insert(path).inserted else { continue }
            candidates.append(
                contentsOf: appURLs(
                    in: URL(fileURLWithPath: path, isDirectory: true),
                    includeOneFolderLevel: includeChildren
                )
            )
        }
        return candidates.compactMap(makeItem)
    }

    static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    static func instanceIdentifier(bundleIdentifier: String, path: String) -> String {
        let canonical = canonicalPath(for: URL(fileURLWithPath: path))
        return "\(bundleIdentifier)::\(canonical)"
    }

    private static func appURLs(in root: URL, includeOneFolderLevel: Bool) -> [URL] {
        let manager = FileManager.default
        guard
            let entries = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        for entry in entries {
            guard !Task.isCancelled else { return result }
            if entry.pathExtension.lowercased() == "app" {
                result.append(entry)
                continue
            }
            guard includeOneFolderLevel,
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                let children = try? manager.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                    options: [.skipsHiddenFiles]
                )
            else { continue }
            result.append(contentsOf: children.filter { $0.pathExtension.lowercased() == "app" })
        }
        return result
    }

    private static func makeItem(_ url: URL) -> AppInfo? {
        let canonicalURL = URL(fileURLWithPath: canonicalPath(for: url))
        guard
            let bundle = Bundle(url: canonicalURL),
            let executableURL = bundle.executableURL,
            FileManager.default.isExecutableFile(atPath: executableURL.path)
        else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let localizedInfo = bundle.localizedInfoDictionary ?? [:]
        if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSUIElement"] as? Bool) == true {
            return nil
        }

        let fallbackName = canonicalURL.deletingPathExtension().lastPathComponent
        let name = preferredDisplayName(
            localizedInfo: localizedInfo,
            info: info,
            fallback: fallbackName
        )
        let normalized = name.lowercased()
        let bundleID = bundle.bundleIdentifier ?? canonicalURL.path

        let deniedFragments = [
            "helper", "renderer", "render engine", "broker", "extension", "uninstaller", "installer",
            "updater", "content manager", "bundle loader", "plugin service", "pluginservice",
        ]
        let exclusionKey = normalized + " " + bundleID.lowercased()
        if deniedFragments.contains(where: exclusionKey.contains) { return nil }
        if bundleID.lowercased().contains("fxplug") { return nil }

        let purpose = purposeLabel(name: name, bundleID: bundleID)
        let category = info["LSApplicationCategoryType"] as? String ?? ""
        let group = groupFor(name: name, bundleID: bundleID, category: category, purpose: purpose)

        return AppInfo(
            id: instanceIdentifier(bundleIdentifier: bundleID, path: canonicalURL.path),
            bundleIdentifier: bundleID,
            name: name,
            chineseName: chineseDisplayName(name: name, bundleID: bundleID),
            path: canonicalURL.path,
            purpose: purpose,
            group: group
        )
    }

    /// Bundle metadata in the wild is not trustworthy: some applications ship
    /// an empty or whitespace-only localized display name. Never allow that
    /// value to become an empty visible label or an unnamed accessibility
    /// element. The application bundle name is the final stable fallback.
    static func preferredDisplayName(
        localizedInfo: [String: Any],
        info: [String: Any],
        fallback: String
    ) -> String {
        let candidates = [
            localizedInfo["CFBundleDisplayName"] as? String,
            localizedInfo["CFBundleName"] as? String,
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String,
            fallback,
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let visible = candidate.zizaiVisibleNonEmpty { return visible }
        }
        return "未命名应用"
    }

    private static func chineseDisplayName(name: String, bundleID: String) -> String {
        let key = (name + " " + bundleID).lowercased()
        if bundleID == "com.apple.mail" { return "邮件" }
        if key.contains("mailmaster") || key.contains("netease.mail") || key.contains("网易邮箱") {
            return "网易邮箱大师"
        }
        let names: [(String, String)] = [
            ("activitymonitor", "活动监视器"), ("activity monitor", "活动监视器"),
            ("airportutility", "AirPort 实用工具"), ("audio midi setup", "音频 MIDI 设置"),
            ("automator", "自动操作"), ("bluetoothfileexchange", "蓝牙文件交换"),
            ("calculator", "计算器"), ("calendar", "日历"), ("chess", "国际象棋"),
            ("colorsyncutility", "ColorSync 实用工具"), ("console", "控制台"),
            ("dictionary", "词典"), ("digitalcolormeter", "数码测色计"),
            ("diskutility", "磁盘工具"), ("findmy", "查找"), ("fontbook", "字体册"),
            ("image_capture", "图像捕捉"), ("image capture", "图像捕捉"),
            ("magnifier", "放大器"), ("maps", "地图"),
            ("messages", "信息"), ("mobilesms", "信息"),
            ("notes", "备忘录"), ("photobooth", "照片亭"), ("photos", "照片"),
            ("podcasts", "播客"), ("preview", "预览"), ("reminders", "提醒事项"),
            ("screensharing", "屏幕共享"), ("shortcuts", "快捷指令"),
            ("stickies", "便笺"), ("stocks", "股市"), ("systempreferences", "系统设置"),
            ("terminal", "终端"), ("textedit", "文本编辑"), ("voice memos", "语音备忘录"),
            ("voicememos", "语音备忘录"), ("weather", "天气"),
            ("wechat", "微信"), ("dingtalk", "钉钉"), ("feishu", "飞书"),
            ("bilibili", "哔哩哔哩"), ("iqiyi", "爱奇艺"),
        ]
        return names.first(where: { key.contains($0.0) })?.1 ?? name
    }

    private static func purposeLabel(name: String, bundleID: String) -> String {
        let key = (name + " " + bundleID).lowercased()
        let rules: [(String, String)] = [
            ("chatgpt", "AI 助手"), ("doubao", "AI 助手"), ("豆包", "AI 助手"),
            ("workbuddy", "AI 工作台"), ("figma", "界面设计"), ("mastergo", "界面设计"),
            ("sketch", "界面设计"), ("aftereffects", "动效设计"), ("after effects", "动效设计"),
            ("剪映", "视频剪辑"), ("capcut", "视频剪辑"), ("cursor", "代码编辑"),
            ("wechat", "微信"), ("微信", "微信"), ("dingtalk", "钉钉"), ("钉钉", "钉钉"),
            ("feishu", "飞书"), ("lark", "飞书"), ("qq", "即时沟通"),
            ("telegram", "即时沟通"), ("whatsapp", "即时沟通"),
            ("notion", "笔记与文档"), ("notes", "备忘录"), ("备忘录", "备忘录"),
            ("reminder", "任务提醒"), ("提醒事项", "任务提醒"),
            ("chrome", "网页浏览"), ("safari", "网页浏览"), ("夸克", "网页浏览"),
            ("keynote", "演示文稿"), ("pages", "文字处理"), ("numbers", "电子表格"),
            ("xmind", "思维导图"), ("爱奇艺", "视频娱乐"), ("bilibili", "视频娱乐"),
            ("哔哩", "视频娱乐"), ("podcast", "播客"), ("播客", "播客"),
            ("music", "音乐"), ("音乐", "音乐"), ("app store", "应用商店"),
            ("preview", "图片与 PDF"), ("预览", "图片与 PDF"), ("finder", "文件管理"),
            ("访达", "文件管理"), ("system settings", "系统设置"), ("系统设置", "系统设置"),
            ("activity monitor", "性能监控"), ("磁盘工具", "磁盘管理"),
            ("calculator", "计算器"), ("计算器", "计算器"), ("calendar", "日历"), ("日历", "日历"),
        ]
        return rules.first(where: { key.contains($0.0) })?.1 ?? "应用"
    }

    private static func groupFor(name: String, bundleID: String, category: String, purpose: String) -> AppGroup {
        let key = (name + " " + bundleID + " " + purpose).lowercased()
        if ["ai ", "chatgpt", "figma", "sketch", "设计", "动效", "剪辑", "cursor", "xcode", "开发"].contains(
            where: key.contains)
        {
            return .aiCreative
        }
        if ["微信", "wechat", "钉钉", "dingtalk", "飞书", "lark", "qq", "telegram", "whatsapp", "meeting", "会议"].contains(
            where: key.contains)
        {
            return .communication
        }
        if ["视频", "音乐", "播客", "game", "游戏", "爱奇艺", "bilibili", "tv", "books", "图书"].contains(where: key.contains)
            || category.contains("entertainment") || category.contains("games")
        {
            return .entertainment
        }
        if ["utility", "系统", "磁盘", "monitor", "网络", "bluetooth", "airport", "设置", "终端", "console"].contains(
            where: key.contains)
            || category.contains("utilities")
        {
            return .utilities
        }
        if ["笔记", "文档", "提醒", "日历", "表格", "演示", "浏览", "邮件", "pdf", "office", "notion"].contains(where: key.contains)
            || category.contains("productivity") || category.contains("business")
        {
            return .productivity
        }
        return .other
    }
}
