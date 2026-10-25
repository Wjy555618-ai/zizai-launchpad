import Foundation
import XCTest

@testable import 自在启动台

final class ApplicationIdentityTests: XCTestCase {
    func testLaunchConfigurationKeepsUnitAndUITestHostsDisjoint() {
        let unitConfiguration = ZizaiLaunchConfiguration.current(
            environment: [ZizaiLaunchConfiguration.unitTestingEnvironmentKey: "1"]
        )
        XCTAssertEqual(unitConfiguration.mode, .unitTestHost)
        XCTAssertEqual(unitConfiguration.applications, [])
        XCTAssertNotNil(unitConfiguration.stateDirectory)

        let uiConfiguration = ZizaiLaunchConfiguration.current(
            environment: [
                ZizaiLaunchConfiguration.uiTestingEnvironmentKey: "1",
                ZizaiLaunchConfiguration.uiTestSessionEnvironmentKey: "launch-mode-test",
            ]
        )
        XCTAssertEqual(uiConfiguration.mode, .uiTesting)
        XCTAssertEqual(uiConfiguration.applications, ZizaiLaunchConfiguration.fixtureApplications)

        let inheritedTestActionConfiguration = ZizaiLaunchConfiguration.current(
            environment: [
                ZizaiLaunchConfiguration.unitTestingEnvironmentKey: "1",
                ZizaiLaunchConfiguration.uiTestingEnvironmentKey: "1",
                ZizaiLaunchConfiguration.uiTestSessionEnvironmentKey: "launch-mode-precedence-test",
            ]
        )
        XCTAssertEqual(inheritedTestActionConfiguration.mode, .uiTesting)
        XCTAssertEqual(
            inheritedTestActionConfiguration.applications,
            ZizaiLaunchConfiguration.fixtureApplications
        )

        let productionConfiguration = ZizaiLaunchConfiguration.current(environment: [:])
        XCTAssertEqual(productionConfiguration.mode, .production)
        XCTAssertNil(productionConfiguration.applications)
        XCTAssertNil(productionConfiguration.stateDirectory)
    }

    func testDisplayNameFallsBackWhenLocalizedMetadataIsBlank() {
        let name = AppScanner.preferredDisplayName(
            localizedInfo: ["CFBundleDisplayName": " \n\t "],
            info: ["CFBundleName": "Fallback Name"],
            fallback: "Bundle Name"
        )

        XCTAssertEqual(name, "Fallback Name")
    }

    func testDisplayNameAlwaysHasAFinalFallback() {
        let name = AppScanner.preferredDisplayName(
            localizedInfo: [:],
            info: [:],
            fallback: "   "
        )

        XCTAssertEqual(name, "未命名应用")
    }

    func testDisplayNameRejectsInvisibleUnicodeMetadata() {
        let name = AppScanner.preferredDisplayName(
            localizedInfo: ["CFBundleDisplayName": "\u{200E}\u{200F}\u{FEFF}"],
            info: ["CFBundleName": "Visible Name"],
            fallback: "Bundle Name"
        )

        XCTAssertEqual(name, "Visible Name")
    }

    func testCatalogSearchDocumentSeparatesVisibleAndTechnicalIdentity() {
        let app = makeApplication(
            id: "wechat",
            bundleIdentifier: "com.tencent.xinWeChat",
            path: "/Applications/WeChat.app"
        )

        let document = ApplicationCatalogLogic.searchDocument(
            for: app,
            displayName: "微信",
            groupName: "沟通协作"
        )

        XCTAssertTrue(document.userFacingTerms.contains("微信聊天"))
        XCTAssertTrue(document.userFacingTerms.contains("WeChat"))
        XCTAssertTrue(document.userFacingTerms.contains("沟通协作"))
        XCTAssertTrue(document.technicalTerms.contains("com.tencent.xinWeChat"))
        XCTAssertTrue(document.technicalTerms.contains("/Applications/WeChat.app"))
    }

    func testSearchPolicyRanksVisibleMatchesAndKeepsFuzzyAsFallback() {
        let figma = ApplicationSearchDocument(
            userFacingTerms: ["Figma"],
            technicalTerms: ["com.figma.Desktop", "/Applications/Figma.app"]
        )
        let bluetooth = ApplicationSearchDocument(
            userFacingTerms: ["蓝牙文件交换", "Bluetooth File Exchange"],
            technicalTerms: ["com.apple.BluetoothFileExchange"]
        )

        XCTAssertEqual(
            ApplicationSearchPolicy.match(query: "fig", document: figma)?.tier,
            .prefix
        )
        XCTAssertEqual(
            ApplicationSearchPolicy.match(query: "fga", document: figma)?.tier,
            .fuzzy
        )
        XCTAssertEqual(
            ApplicationSearchPolicy.match(query: "fig", document: bluetooth)?.tier,
            .fuzzy
        )

        let matches = [
            (value: "Figma", match: ApplicationSearchMatch(tier: .prefix, detailScore: 2)),
            (value: "Noise", match: ApplicationSearchMatch(tier: .fuzzy, detailScore: 900)),
        ]
        XCTAssertEqual(ApplicationSearchPolicy.preferredMatches(matches).map(\.value), ["Figma"])
    }

    func testSearchPolicyCoversExactSubstringNormalizationAndFuzzyOnlyResults() {
        let document = ApplicationSearchDocument(
            userFacingTerms: ["Créative Studio"],
            technicalTerms: ["com.example.studio", "/Applications/Studio.app"]
        )

        XCTAssertEqual(
            ApplicationSearchPolicy.match(query: "creative studio", document: document)?.tier,
            .exact
        )
        XCTAssertEqual(
            ApplicationSearchPolicy.match(query: "studio", document: document)?.tier,
            .substring
        )
        XCTAssertEqual(
            ApplicationSearchPolicy.normalize("ＦＩＧＭＡ"),
            "figma"
        )

        let fuzzyOnly = [
            (value: "first", match: ApplicationSearchMatch(tier: .fuzzy, detailScore: 200)),
            (value: "second", match: ApplicationSearchMatch(tier: .fuzzy, detailScore: 400)),
        ]
        XCTAssertEqual(
            ApplicationSearchPolicy.preferredMatches(fuzzyOnly).map(\.value),
            ["first", "second"]
        )
        let empty: [(value: String, match: ApplicationSearchMatch)] = []
        XCTAssertTrue(ApplicationSearchPolicy.preferredMatches(empty).isEmpty)
    }

    func testTechnicalIdentityDoesNotParticipateInFuzzyMatching() {
        let document = ApplicationSearchDocument(
            userFacingTerms: ["TestFlight"],
            technicalTerms: ["com.apple.TestFlight", "/Applications/TestFlight.app"]
        )

        XCTAssertNotNil(ApplicationSearchPolicy.match(query: "apple", document: document))
        XCTAssertNil(ApplicationSearchPolicy.match(query: "apl", document: document))
    }

    func testLegacyIdentityMigrationMovesStateToOneStableInstance() {
        let app = makeApplication(
            id: "stable-instance",
            bundleIdentifier: "example.product",
            path: "/Applications/Product.app"
        )
        var state = PersistedState()
        state.aliases[app.bundleIdentifier] = "主力版"
        state.hiddenAppIDs.insert(app.bundleIdentifier)
        state.groupAppOrder[AppGroup.aiCreative.stableID] = [app.bundleIdentifier]

        ApplicationCatalogLogic.migrateLegacyIdentity(state: &state, apps: [app])

        XCTAssertEqual(state.aliases[app.id], "主力版")
        XCTAssertTrue(state.hiddenAppIDs.contains(app.id))
        XCTAssertFalse(state.hiddenAppIDs.contains(app.bundleIdentifier))
        XCTAssertEqual(state.groupAppOrder[AppGroup.aiCreative.stableID], [app.id])
    }

    @MainActor
    func testSameNameApplicationsRemainDistinguishableAcrossBundleIdentifiers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let applications = [
            makeApplication(
                id: "stable", bundleIdentifier: "example.figma.stable",
                path: "/Applications/Figma.app"
            ),
            makeApplication(
                id: "preview", bundleIdentifier: "example.figma.preview",
                path: "/Applications/Figma Preview.app"
            ),
        ]
        let store = LauncherStore(stateDirectory: directory, appProvider: { applications })

        XCTAssertEqual(Set(applications.map { store.displayName(for: $0) }).count, 2)
        XCTAssertTrue(applications.allSatisfy { store.instanceLabel(for: $0) != nil })
    }

    private func makeApplication(id: String, bundleIdentifier: String, path: String) -> AppInfo {
        AppInfo(
            id: id,
            bundleIdentifier: bundleIdentifier,
            name: "Figma",
            chineseName: "Figma",
            path: path,
            purpose: "界面设计",
            group: .aiCreative
        )
    }
}
