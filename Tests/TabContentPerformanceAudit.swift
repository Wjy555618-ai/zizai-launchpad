import AppKit
import SwiftUI

@main
@MainActor
enum TabContentPerformanceAudit {
    static func main() {
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-tab-content-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let apps = AppScanner.scan()
        let store = LauncherStore(stateDirectory: stateDirectory, appProvider: { apps })
        store.state.hasSeenWelcome = true
        IconCache.shared.prewarm(paths: apps.map(\.path))
        let layoutModeController = LayoutModeController(selection: store.layoutMode)

        let hosting = NSHostingView(
            rootView: RootView(layoutModeController: layoutModeController)
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
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        hosting.displayIfNeeded()

        let modes: [LayoutMode] = [.space, .allApps, .groups]
        // Use enough samples for P95 to describe sustained behavior instead
        // of collapsing to the single slowest frame (18 samples made P95 and
        // max the same value). The independent max gate below still catches
        // a genuinely unacceptable one-off stall.
        let sampleCount = 60
        var batchP95s: [Double] = []
        var allLabeledSamples: [(LayoutMode, Double)] = []

        // WindowServer may still be retiring the preceding compiler's GPU work
        // when this standalone audit starts. Use three complete sustained
        // batches and gate on their median P95. Across all 180 switches, P99
        // must remain below two frames and the absolute peak below 80ms. This
        // catches repeated stutter and genuine stalls without treating one or
        // two WindowServer scheduler hiccups as a product regression.
        for batchIndex in 0..<3 {
            if batchIndex > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }

            var samples: [Double] = []
            for index in 0..<sampleCount {
                let mode = modes[index % modes.count]
                let start = DispatchTime.now().uptimeNanoseconds
                layoutModeController.selection = mode
                store.stageLayoutModePersistence(mode)
                hosting.layoutSubtreeIfNeeded()
                let end = DispatchTime.now().uptimeNanoseconds
                let duration = Double(end - start) / 1_000_000
                samples.append(duration)
                allLabeledSamples.append((mode, duration))
            }

            let sorted = samples.sorted()
            batchP95s.append(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))])
        }

        let sortedBatchP95s = batchP95s.sorted()
        let representativeP95 = sortedBatchP95s[sortedBatchP95s.count / 2]
        let allSamples = allLabeledSamples.map(\.1).sorted()
        let p99Index = min(allSamples.count - 1, Int(Double(allSamples.count - 1) * 0.99))
        let combinedP99 = allSamples[p99Index]
        let absoluteMaximum = allSamples.last ?? .infinity
        if representativeP95 >= 16.7 || combinedP99 >= 34 || absoluteMaximum >= 80 {
            let details =
                allLabeledSamples
                .map { "\($0.0.rawValue)=\(format($0.1))ms" }
                .joined(separator: "，")
            print("页面切换逐次耗时：\(details)")
        }
        require(
            representativeP95 < 16.7,
            "真实页面切换三批中位 P95 超过一帧 16.7ms：\(format(representativeP95))ms"
        )
        require(
            combinedP99 < 34,
            "真实页面切换整体 P99 超过两帧 34ms：\(format(combinedP99))ms"
        )
        require(
            absoluteMaximum < 80,
            "真实页面切换单次绝对峰值超过 80ms：\(format(absoluteMaximum))ms"
        )

        let batchSummary = batchP95s.map(format).joined(separator: "ms / ")
        print(
            "页面切换首帧准备验收通过：3 批各 \(sampleCount) 次切换，"
                + "P95 \(batchSummary)ms，中位 \(format(representativeP95))ms，"
                + "整体 P99 \(format(combinedP99))ms，"
                + "绝对峰值 \(format(absoluteMaximum))ms。"
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("页面切换渲染验收失败：\(message)\n".utf8))
        exit(1)
    }
}
