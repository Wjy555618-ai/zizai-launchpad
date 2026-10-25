import Foundation
import XCTest

@testable import 自在启动台

final class AppScannerTests: XCTestCase {
    func testAdditionalRootDiscoversNestedAppsAndClassifiesMetadata() throws {
        let fixture = try AppBundleFixture()
        defer { fixture.remove() }
        let nestedFolder = fixture.root.appendingPathComponent("Design", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        let appURL = try fixture.makeApp(
            named: "Figma Preview",
            in: nestedFolder,
            bundleIdentifier: "com.example.figma.preview",
            displayName: "Figma Preview",
            category: "public.app-category.graphics-design"
        )

        let apps = AppScanner.scan(additionalApplicationRoots: [fixture.root])
        let app = try XCTUnwrap(apps.first { $0.path == appURL.standardizedFileURL.path })

        XCTAssertEqual(
            app.id,
            AppScanner.instanceIdentifier(
                bundleIdentifier: "com.example.figma.preview",
                path: appURL.path
            )
        )
        XCTAssertEqual(app.name, "Figma Preview")
        XCTAssertEqual(app.purpose, "界面设计")
        XCTAssertEqual(app.group, .aiCreative)
    }

    func testScannerRejectsBackgroundHelpersAndMalformedBundles() throws {
        let fixture = try AppBundleFixture()
        defer { fixture.remove() }
        _ = try fixture.makeApp(
            named: "Visible Product",
            bundleIdentifier: "com.example.visible",
            displayName: "Visible Product"
        )
        _ = try fixture.makeApp(
            named: "Background Agent",
            bundleIdentifier: "com.example.background",
            displayName: "Background Agent",
            additionalInfo: ["LSBackgroundOnly": true]
        )
        _ = try fixture.makeApp(
            named: "Menu Agent",
            bundleIdentifier: "com.example.menu",
            displayName: "Menu Agent",
            additionalInfo: ["LSUIElement": true]
        )
        _ = try fixture.makeApp(
            named: "Product Helper",
            bundleIdentifier: "com.example.helper",
            displayName: "Product Helper"
        )
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent("Malformed.app", isDirectory: true),
            withIntermediateDirectories: true
        )

        let matchingApps = AppScanner.scanCandidates(additionalApplicationRoots: [fixture.root])
            .filter { $0.path.hasPrefix(fixture.root.path) }

        XCTAssertEqual(matchingApps.map(\.name), ["Visible Product"])
    }

    func testScannerPreservesDifferentInstancesAndDeduplicatesEquivalentRoots() throws {
        let fixture = try AppBundleFixture()
        defer { fixture.remove() }
        let firstURL = try fixture.makeApp(
            named: "Product Stable",
            bundleIdentifier: "com.example.product",
            displayName: "Product"
        )
        let secondURL = try fixture.makeApp(
            named: "Product Preview",
            bundleIdentifier: "com.example.product",
            displayName: "Product"
        )

        let apps = AppScanner.scan(additionalApplicationRoots: [fixture.root, fixture.root])
            .filter { $0.path.hasPrefix(fixture.root.path) }

        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(Set(apps.map(\.bundleIdentifier)), ["com.example.product"])
        XCTAssertEqual(Set(apps.map(\.path)), Set([firstURL.path, secondURL.path]))
        XCTAssertEqual(Set(apps.map(\.id)).count, 2)
    }

    func testCanonicalIdentityResolvesSymlinkAliases() throws {
        let fixture = try AppBundleFixture()
        defer { fixture.remove() }
        let appURL = try fixture.makeApp(
            named: "Canonical",
            bundleIdentifier: "com.example.canonical",
            displayName: "Canonical"
        )
        let aliasURL = fixture.root.appendingPathComponent("Canonical Alias.app")
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: appURL)

        XCTAssertEqual(AppScanner.canonicalPath(for: appURL), AppScanner.canonicalPath(for: aliasURL))
        XCTAssertEqual(
            AppScanner.instanceIdentifier(
                bundleIdentifier: "com.example.canonical",
                path: appURL.path
            ),
            AppScanner.instanceIdentifier(
                bundleIdentifier: "com.example.canonical",
                path: aliasURL.path
            )
        )
    }
}

private struct AppBundleFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-app-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeApp(
        named name: String,
        in parent: URL? = nil,
        bundleIdentifier: String,
        displayName: String,
        category: String? = nil,
        additionalInfo: [String: Any] = [:]
    ) throws -> URL {
        let appURL = (parent ?? root).appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": displayName,
            "CFBundleDisplayName": displayName,
            "CFBundleExecutable": "TestExecutable",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        if let category {
            info["LSApplicationCategoryType"] = category
        }
        info.merge(additionalInfo) { _, replacement in replacement }
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"), options: .atomic)
        let executableURL =
            contentsURL
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("TestExecutable")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        return appURL.standardizedFileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
