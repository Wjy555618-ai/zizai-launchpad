import AppKit
import Foundation

@main
@MainActor
enum AsyncWorkPerformanceAudit {
    static func main() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-async-work-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = AppInfo(
            id: "test.app::/Applications/Test.app",
            bundleIdentifier: "test.app",
            name: "Test",
            chineseName: "测试应用",
            path: "/Applications/Test.app",
            purpose: "测试",
            group: .productivity
        )
        // A single wall-clock maximum mistakes one hosted-runner scheduling
        // preemption for product work. Repeat the complete scan independently
        // and gate on the median batch maximum: a real main-actor regression
        // repeats, while one unrelated host stall cannot clear or fail the
        // product contract by itself. The 40ms limit remains unchanged.
        var stores: [LauncherStore] = []
        var stateDirectories: [URL] = []
        var scanBatchMaximums: [Double] = []
        for batchIndex in 0..<3 {
            let stateDirectory = root.appendingPathComponent(
                "batch-\(batchIndex)",
                isDirectory: true
            )
            let access = ApplicationFolderAccess(storageDirectory: stateDirectory) { _ in
                Thread.sleep(forTimeInterval: 0.16)
                return [app]
            }
            let store = LauncherStore(
                stateDirectory: stateDirectory,
                asyncAppProvider: { await access.scanApplicationsAsync() },
                isAppScanComplete: { true },
                backgroundPersistenceEnabled: true
            )

            require(store.isReloadingApps, "第 \(batchIndex + 1) 批后台扫描未进入进行中状态")
            var previousTick = DispatchTime.now().uptimeNanoseconds
            var largestMainActorGap = 0.0
            let deadline = Date().addingTimeInterval(2)
            while store.isReloadingApps && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(5))
                let now = DispatchTime.now().uptimeNanoseconds
                largestMainActorGap = max(
                    largestMainActorGap,
                    Double(now - previousTick) / 1_000_000
                )
                previousTick = now
            }

            require(!store.isReloadingApps, "第 \(batchIndex + 1) 批后台扫描超时")
            require(store.apps == [app], "第 \(batchIndex + 1) 批后台扫描结果没有在主线程一次性提交")
            stores.append(store)
            stateDirectories.append(stateDirectory)
            scanBatchMaximums.append(largestMainActorGap)
        }

        let sortedScanBatchMaximums = scanBatchMaximums.sorted()
        let representativeScanMaximum = sortedScanBatchMaximums[sortedScanBatchMaximums.count / 2]
        require(
            representativeScanMaximum < 40,
            "三批扫描的中位最大主线程停顿 \(format(representativeScanMaximum))ms"
        )
        guard let store = stores.last, let stateDirectory = stateDirectories.last else {
            fail("后台扫描没有生成可用于持久化验收的状态")
        }

        for index in 0..<8_000 {
            store.state.aliases["bulk-\(index)"] = String(repeating: "布局数据", count: 32)
        }
        let saveStart = DispatchTime.now().uptimeNanoseconds
        store.state.aliases[app.id] = "后台保存"
        store.updatePosition(CGPoint(x: 24, y: 36), for: app, persist: true)
        let saveReturn = Double(DispatchTime.now().uptimeNanoseconds - saveStart) / 1_000_000
        require(saveReturn < 30, "布局保存阻塞主线程 \(format(saveReturn))ms")

        store.flushPendingPersistence()
        let stateURL = stateDirectory.appendingPathComponent("布局.json")
        guard let data = try? Data(contentsOf: stateURL),
            let persisted = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            fail("后台保存没有产生可恢复的布局文件")
        }
        require(persisted.aliases[app.id] == "后台保存", "终止刷盘丢失最新状态")

        let scanBatchSummary = scanBatchMaximums.map(format).joined(separator: "ms / ")
        print(
            "后台工作验收通过：3 批 160ms 扫描的主线程最大间隔 "
                + "\(scanBatchSummary)ms，中位 \(format(representativeScanMaximum))ms；大布局保存调用 "
                + "\(format(saveReturn))ms 返回，终止刷盘完整。"
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("后台工作验收失败：\(message)\n".utf8))
        exit(1)
    }
}
