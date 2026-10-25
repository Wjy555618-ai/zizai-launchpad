import AppKit
import SwiftUI
import XCTest

@testable import 自在启动台

@MainActor
final class ViewCompositionTests: XCTestCase {
    func testSparseSearchResultsDoNotReserveInvisibleColumns() {
        XCTAssertEqual(
            SearchResultsGridLayout.maximumWidth(resultCount: 0, spacing: 24),
            340
        )
        XCTAssertEqual(
            SearchResultsGridLayout.maximumWidth(resultCount: 2, spacing: 24),
            704
        )
        XCTAssertEqual(
            SearchResultsGridLayout.maximumWidth(resultCount: 8, spacing: 24),
            1_068
        )
    }

    func testEveryPersistentPrimarySurfaceSurvivesRuntimeAppearanceChanges() {
        withStore { store in
            let controller = LayoutModeController(selection: .groups)
            let hosting = NSHostingView(
                rootView: RootView(layoutModeController: controller)
                    .environmentObject(store)
            )
            hosting.frame = CGRect(x: 0, y: 0, width: 1_360, height: 860)

            let window = NSWindow(
                contentRect: hosting.bounds,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.orderBack(nil)
            defer { window.close() }

            for appearanceName in [
                NSAppearance.Name.darkAqua,
                NSAppearance.Name.aqua,
                NSAppearance.Name.accessibilityHighContrastDarkAqua,
                NSAppearance.Name.accessibilityHighContrastAqua,
            ] {
                let appearance = NSAppearance(named: appearanceName)
                window.appearance = appearance
                hosting.appearance = appearance
                hosting.layoutSubtreeIfNeeded()
                pumpMainRunLoop(for: 0.12)

                for mode in LayoutMode.allCases {
                    controller.selection = mode
                    hosting.layoutSubtreeIfNeeded()
                    pumpMainRunLoop(for: 0.03)

                    XCTAssertEqual(controller.selection, mode)
                    XCTAssertFalse(hosting.frame.isEmpty)
                    XCTAssertGreaterThan(hosting.subviews.count, 0)
                }
            }
        }
    }

    func testProductSheetsComposeFromTheSameDeterministicState() {
        withStore { store in
            guard let application = store.apps.first else {
                return XCTFail("Missing deterministic application fixture")
            }

            assertViewComposes(
                WelcomeSheet(onStart: {}),
                size: CGSize(width: 720, height: 460)
            )
            assertViewComposes(
                HelpSheet(),
                size: CGSize(width: 650, height: 650)
            )
            assertViewComposes(
                GroupEditorSheet(
                    draft: GroupDraft(
                        editingGroupID: nil,
                        name: "设计协作",
                        tint: .indigo,
                        center: .zero
                    ),
                    onSave: { _, _ in }
                ),
                size: CGSize(width: 460, height: 420)
            )
            assertViewComposes(
                AliasEditor(app: application, draft: .constant("工作入口"))
                    .environmentObject(store),
                size: CGSize(width: 440, height: 320)
            )
        }
    }

    private func withStore(_ body: (LauncherStore) -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-view-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let applications = ZizaiLaunchConfiguration.fixtureApplications
        let store = LauncherStore(
            stateDirectory: directory,
            appProvider: { applications }
        )
        store.state.hasSeenWelcome = true
        body(store)
    }

    private func assertViewComposes<Content: View>(
        _ content: Content,
        size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertFalse(hosting.frame.isEmpty, file: file, line: line)
        XCTAssertGreaterThan(hosting.subviews.count, 0, file: file, line: line)
        XCTAssertTrue(hosting.fittingSize.width.isFinite, file: file, line: line)
        XCTAssertTrue(hosting.fittingSize.height.isFinite, file: file, line: line)
    }

    private func pumpMainRunLoop(for duration: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }
}
