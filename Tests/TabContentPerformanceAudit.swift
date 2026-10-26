import AppKit
import Darwin
import SwiftUI

@MainActor
enum TabContentPerformanceAudit {
    static func run() {
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-tab-content-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let apps = AppScanner.scan()
        let store = LauncherStore(stateDirectory: stateDirectory, appProvider: { apps })
        store.state.hasSeenWelcome = true
        IconCache.shared.prewarm(paths: apps.map(\.path))
        let layoutModeController = LayoutModeController(selection: store.layoutMode)
        var didCompleteLaunchPrewarm = false

        let hosting = NSHostingView(
            rootView: RootView(
                layoutModeController: layoutModeController,
                onLaunchPrewarmCompleted: {
                    didCompleteLaunchPrewarm = true
                }
            )
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
        let prewarmDeadline = Date().addingTimeInterval(5)
        while !didCompleteLaunchPrewarm && Date() < prewarmDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        require(didCompleteLaunchPrewarm, "生产页面预热没有在 5 秒内完成")
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let calibration = measureCPUCalibration()
        require(
            calibration.medianMilliseconds >= 3 && calibration.medianMilliseconds <= 30,
            "托管机 CPU 标定超出可信范围：\(format(calibration.medianMilliseconds))ms"
        )
        // GitHub's shared Apple-silicon runners can vary their effective CPU
        // allocation substantially between otherwise identical jobs. Express
        // the frame budgets in stable reference-machine units while retaining
        // raw CPU telemetry and the independent absolute-stall gate below.
        let referenceCalibrationMilliseconds = 9.5
        let cpuNormalizationScale = calibration.medianMilliseconds / referenceCalibrationMilliseconds

        let modes: [LayoutMode] = [.space, .allApps, .groups]
        // Use enough samples for P95 to describe sustained behavior instead
        // of collapsing to the single slowest frame (18 samples made P95 and
        // max the same value). The independent max gate below still catches
        // a genuinely unacceptable one-off stall.
        let sampleCount = 60
        var batchWallP95s: [Double] = []
        var batchCPUP95s: [Double] = []
        var allLabeledSamples: [(mode: LayoutMode, wall: Double, cpu: Double)] = []

        // A hosted runner can deschedule this process or WindowServer in the
        // middle of a switch, so wall time includes external waits that the
        // product does not control. Preserve every wall sample as diagnostic
        // telemetry, but apply the unchanged one-frame P95 and two-frame P99
        // budgets to main-thread CPU time. Three independent batches keep the
        // sustained-work signal representative while the absolute CPU gate
        // still catches a single severe product regression.
        for batchIndex in 0..<3 {
            if batchIndex > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            }

            var wallSamples: [Double] = []
            var cpuSamples: [Double] = []
            for index in 0..<sampleCount {
                let mode = modes[index % modes.count]
                let (wallDuration, cpuDuration) = autoreleasepool {
                    let wallStart = DispatchTime.now().uptimeNanoseconds
                    let cpuStart = threadCPUTimeNanoseconds()
                    layoutModeController.selection = mode
                    store.stageLayoutModePersistence(mode)
                    hosting.layoutSubtreeIfNeeded()
                    let cpuEnd = threadCPUTimeNanoseconds()
                    let wallEnd = DispatchTime.now().uptimeNanoseconds
                    return (
                        Double(wallEnd - wallStart) / 1_000_000,
                        Double(cpuEnd - cpuStart) / 1_000_000
                    )
                }
                wallSamples.append(wallDuration)
                cpuSamples.append(cpuDuration)
                allLabeledSamples.append((mode, wallDuration, cpuDuration))

                // A real second click cannot arrive before AppKit finishes the
                // current event. Drain deferred display work between samples
                // so one synthetic click is never charged for its predecessor.
                hosting.displayIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }

            let sortedWall = wallSamples.sorted()
            let sortedCPU = cpuSamples.sorted()
            let p95Index = min(wallSamples.count - 1, Int(Double(wallSamples.count) * 0.95))
            batchWallP95s.append(sortedWall[p95Index])
            batchCPUP95s.append(sortedCPU[p95Index])
        }

        let sortedBatchWallP95s = batchWallP95s.sorted()
        let representativeWallP95 = sortedBatchWallP95s[sortedBatchWallP95s.count / 2]
        let sortedBatchCPUP95s = batchCPUP95s.sorted()
        let representativeCPUP95 = sortedBatchCPUP95s[sortedBatchCPUP95s.count / 2]
        let allWallSamples = allLabeledSamples.map(\.wall).sorted()
        let allCPUSamples = allLabeledSamples.map(\.cpu).sorted()
        let p99Index = min(
            allWallSamples.count - 1,
            Int(Double(allWallSamples.count - 1) * 0.99)
        )
        let combinedWallP99 = allWallSamples[p99Index]
        let combinedRawCPUP99 = allCPUSamples[p99Index]
        let absoluteWallMaximum = allWallSamples.last ?? .infinity
        let absoluteCPUMaximum = allCPUSamples.last ?? .infinity
        let representativeNormalizedCPUP95 = representativeCPUP95 / cpuNormalizationScale
        let combinedNormalizedCPUP99 = combinedRawCPUP99 / cpuNormalizationScale
        if representativeNormalizedCPUP95 >= 16.7 || combinedNormalizedCPUP99 >= 34
            || absoluteCPUMaximum >= 80
        {
            let details =
                allLabeledSamples
                .map {
                    "\($0.mode.rawValue)=wall \(format($0.wall))ms/cpu \(format($0.cpu))ms"
                }
                .joined(separator: "，")
            print("页面切换逐次耗时：\(details)")
        }
        require(
            representativeNormalizedCPUP95 < 16.7,
            "真实页面切换三批中位标准化 CPU P95 超过一帧 16.7ms："
                + "\(format(representativeNormalizedCPUP95))ms（原始 \(format(representativeCPUP95))ms）"
        )
        require(
            combinedNormalizedCPUP99 < 34,
            "真实页面切换整体标准化 CPU P99 超过两帧 34ms："
                + "\(format(combinedNormalizedCPUP99))ms（原始 \(format(combinedRawCPUP99))ms）"
        )
        require(
            absoluteCPUMaximum < 80,
            "真实页面切换单次主线程 CPU 峰值超过 80ms：\(format(absoluteCPUMaximum))ms"
        )

        let batchWallSummary = batchWallP95s.map(format).joined(separator: "ms / ")
        let batchCPUSummary = batchCPUP95s.map(format).joined(separator: "ms / ")
        print(
            "页面切换首帧准备验收通过：3 批各 \(sampleCount) 次切换，"
                + "wall P95 \(batchWallSummary)ms，中位 \(format(representativeWallP95))ms，"
                + "整体 wall P99 \(format(combinedWallP99))ms；"
                + "原始 CPU P95 \(batchCPUSummary)ms，中位 \(format(representativeCPUP95))ms，"
                + "整体原始 CPU P99 \(format(combinedRawCPUP99))ms；"
                + "标定 \(format(calibration.medianMilliseconds))ms（校验 \(String(calibration.digest, radix: 16))），"
                + "标准化比例 \(format(cpuNormalizationScale))，"
                + "标准化 CPU P95 \(format(representativeNormalizedCPUP95))ms / "
                + "P99 \(format(combinedNormalizedCPUP99))ms，"
                + "wall 绝对峰值 \(format(absoluteWallMaximum))ms，"
                + "主线程 CPU 峰值 \(format(absoluteCPUMaximum))ms。"
        )
    }

    private static func measureCPUCalibration() -> (medianMilliseconds: Double, digest: UInt64) {
        var samples: [Double] = []
        var digest = DispatchTime.now().uptimeNanoseconds
        for index in 0..<7 {
            let start = threadCPUTimeNanoseconds()
            digest ^= calibrationWorkload(seed: digest &+ UInt64(index))
            samples.append(Double(threadCPUTimeNanoseconds() - start) / 1_000_000)
        }
        let sorted = samples.sorted()
        return (sorted[sorted.count / 2], digest)
    }

    @inline(never)
    private static func calibrationWorkload(seed: UInt64) -> UInt64 {
        var value = seed
        for index in 0..<6_000_000 {
            value = value &* 6_364_136_223_846_793_005 &+ UInt64(index) &+ 1_442_695_040_888_963_407
            value ^= value >> 29
        }
        return value
    }

    private static func threadCPUTimeNanoseconds() -> UInt64 {
        var time = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0 else {
            fail("无法读取主线程 CPU 时钟")
        }
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
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
