import AppKit
import Foundation

@main
enum ScannerAudit {
    static func main() {
        let apps = AppScanner.scan()
        require(!apps.isEmpty, "没有扫描到任何应用")
        require(Set(apps.map(\.id)).count == apps.count, "扫描结果包含重复应用标识")
        require(Set(apps.map(\.path)).count == apps.count, "同一个应用路径被重复收录")
        require(
            apps.allSatisfy { !$0.name.zizaiVisibleTrimmed.isEmpty },
            "扫描结果包含空应用名称"
        )
        require(
            apps.allSatisfy { !$0.chineseName.zizaiVisibleTrimmed.isEmpty },
            "扫描结果包含空本地化名称"
        )

        require(
            AppScanner.preferredDisplayName(
                localizedInfo: ["CFBundleDisplayName": "   "],
                info: ["CFBundleName": "Fallback Name"],
                fallback: "Bundle Name"
            ) == "Fallback Name",
            "空白本地化名称没有正确回退"
        )
        require(
            AppScanner.preferredDisplayName(
                localizedInfo: ["CFBundleDisplayName": "\u{200E}\u{200F}"],
                info: ["CFBundleName": "Visible Name"],
                fallback: "Bundle Name"
            ) == "Visible Name",
            "不可见格式字符名称没有正确回退"
        )

        let candidates = AppScanner.scanCandidates()
        let candidateFamilies = Dictionary(grouping: candidates, by: \.bundleIdentifier)
        let scannedFamilies = Dictionary(grouping: apps, by: \.bundleIdentifier)
        var multiInstanceFamilyCount = 0
        for (bundleID, family) in candidateFamilies {
            let expectedPaths = Set(family.map(\.path))
            guard expectedPaths.count > 1 else { continue }
            multiInstanceFamilyCount += 1
            let actualPaths = Set((scannedFamilies[bundleID] ?? []).map(\.path))
            require(
                actualPaths == expectedPaths,
                "同系列应用副本没有全部保留：\(bundleID)"
            )
        }

        let photoshop2024 = AppScanner.instanceIdentifier(
            bundleIdentifier: "com.adobe.Photoshop",
            path: "/Applications/Adobe Photoshop 2024.app"
        )
        let photoshop2025 = AppScanner.instanceIdentifier(
            bundleIdentifier: "com.adobe.Photoshop",
            path: "/Applications/Adobe Photoshop 2025.app"
        )
        require(photoshop2024 != photoshop2025, "同 Bundle ID 的不同版本仍会被错误合并")
        require(
            photoshop2024
                == AppScanner.instanceIdentifier(
                    bundleIdentifier: "com.adobe.Photoshop",
                    path: "/Applications/./Adobe Photoshop 2024.app"
                ),
            "同一路径的等价写法没有被稳定去重"
        )

        let denied = [
            "helper", "renderer", "broker", "uninstaller", "installer", "updater",
            "plugin service", "pluginservice",
        ]
        for app in apps {
            let key = "\(app.name) \(app.bundleIdentifier)".lowercased()
            require(!denied.contains(where: key.contains), "误收录内部组件：\(app.name)")
        }

        testExplicitAdditionalFolder()

        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let userApps = AppScanner.scan(additionalApplicationRoots: [userApplications])
        let expectedChromeApps: [(String, String)] = [
            ("Chrome Apps.localized/GitHub.app", "com.google.Chrome.app.mjoklplbddabcmpepnokjaffbmgbkkgg"),
            ("Chrome Apps.localized/Linear.app", "com.google.Chrome.app.bgdbmehlmdmddlgneophbcddadgknlpm"),
        ]
        for (relativePath, bundleID) in expectedChromeApps {
            let path = userApplications.appendingPathComponent(relativePath).path
            if FileManager.default.fileExists(atPath: path) {
                require(
                    userApps.contains(where: {
                        $0.bundleIdentifier == bundleID
                            && AppScanner.canonicalPath(for: URL(fileURLWithPath: $0.path))
                                == AppScanner.canonicalPath(for: URL(fileURLWithPath: path))
                    }),
                    "漏掉用户应用：\(relativePath)"
                )
            }
        }

        let figmaPaths = ["/Applications/Figma.app", "/Applications/Figma+EX.app"]
            .filter { FileManager.default.fileExists(atPath: $0) }
        if figmaPaths.count == 2 {
            let figmaApps = apps.filter { $0.bundleIdentifier == "com.figma.Desktop" }
            require(figmaApps.count >= 2, "同 Bundle ID 的两个 Figma 仍有一个被吞掉")
            for path in figmaPaths {
                let canonical = AppScanner.canonicalPath(for: URL(fileURLWithPath: path))
                require(figmaApps.contains(where: { $0.path == canonical }), "漏掉真实应用：\(path)")
            }
        }

        let ambiguousMailNames = apps.filter {
            $0.chineseName == "邮件" && $0.bundleIdentifier != "com.apple.mail"
        }
        require(ambiguousMailNames.isEmpty, "第三方邮箱被错误显示为系统“邮件”")

        if ProcessInfo.processInfo.environment["ZIZAI_SCANNER_AUDIT_VERBOSE"] == "1" {
            for app in apps {
                print(
                    "\(app.bundleIdentifier)\t\(String(reflecting: app.name))"
                        + "\t\(String(reflecting: app.chineseName))\t\(app.path)"
                )
            }
        }

        print(
            "应用扫描验收通过：\(apps.count) 个可启动应用；逐个复核 \(multiInstanceFamilyCount) 个多实例家族，同 Bundle ID 多版本、等价路径去重、授权附加目录、内部组件过滤和显示名称均正常。"
        )
    }

    private static func testExplicitAdditionalFolder() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-scanner-extra-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("Authorized Sample.app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": "test.zizai.authorized-sample",
                "CFBundleName": "Authorized Sample",
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        } catch {
            fail("无法创建授权目录扫描样本：\(error.localizedDescription)")
        }

        require(
            !AppScanner.scan().contains(where: { $0.bundleIdentifier == "test.zizai.authorized-sample" }),
            "未授权的附加目录被静默扫描"
        )
        let authorized = AppScanner.scan(additionalApplicationRoots: [root])
        require(
            authorized.contains(where: { $0.bundleIdentifier == "test.zizai.authorized-sample" }),
            "用户授权后仍未扫描附加应用目录"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("应用扫描验收失败：\(message)\n".utf8))
            exit(1)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("应用扫描验收失败：\(message)\n".utf8))
        exit(1)
    }
}
