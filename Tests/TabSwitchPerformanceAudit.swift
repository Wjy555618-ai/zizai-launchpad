import AppKit
import Foundation

@main
@MainActor
enum TabSwitchPerformanceAudit {
    static func main() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-tab-switch-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let apps = AppScanner.scan()
        let store = LauncherStore(stateDirectory: root, appProvider: { apps })
        let modes = LayoutMode.allCases
        var samples: [Double] = []

        for index in 0..<180 {
            let mode = modes[index % modes.count]
            let start = DispatchTime.now().uptimeNanoseconds
            store.layoutMode = mode
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
            require(store.layoutMode == mode, "Tab 选择没有在当前事件中立即更新")
        }

        let sorted = samples.sorted()
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let maximum = sorted.last ?? .infinity
        require(p95 < 2, "Tab 切换 P95 超过 2ms：\(format(p95))ms")
        require(maximum < 8, "Tab 切换峰值超过 8ms：\(format(maximum))ms")

        let expectedMode = store.layoutMode
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        let stateURL = root.appendingPathComponent("布局.json")
        guard let data = try? Data(contentsOf: stateURL),
            let persisted = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            fail("延迟保存没有生成可用布局")
        }
        require(persisted.layoutMode == expectedMode, "Tab 切换后的视图选择没有正确持久化")

        print("Tab 切换性能验收通过：180 次即时切换，P95 \(format(p95))ms，峰值 \(format(maximum))ms；延迟持久化正常。")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Tab 切换性能验收失败：\(message)\n".utf8))
        exit(1)
    }
}
