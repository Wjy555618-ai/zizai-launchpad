import AppKit
import Combine
import Foundation

@MainActor
enum CanvasInteractionPerformanceAudit {
    static func run() {
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zizai-canvas-performance-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let apps = AppScanner.scan()
        let store = LauncherStore(stateDirectory: stateDirectory, appProvider: { apps })
        guard let app = store.visibleApps.first,
            let group = store.group(for: app)
        else {
            fail("没有可用应用或分组，无法执行拖动性能验收")
        }

        var publicationCount = 0
        let publication = store.objectWillChange.sink {
            publicationCount += 1
        }

        let frame = CGRect(
            x: group.center.x - group.size.width / 2,
            y: group.center.y - group.size.height / 2,
            width: group.size.width,
            height: group.size.height
        )
        let sampleCount = 720
        var samples: [Double] = []
        samples.reserveCapacity(sampleCount)
        var finalPoint = group.center.point

        for index in 0..<sampleCount {
            let progress = CGFloat(index) / CGFloat(max(1, sampleCount - 1))
            finalPoint = CGPoint(
                x: frame.minX + frame.width * (0.12 + progress * 0.76),
                y: frame.midY + sin(progress * .pi * 8) * frame.height * 0.28
            )
            let start = DispatchTime.now().uptimeNanoseconds
            _ = store.interactiveAppMovePreview(app, to: finalPoint)
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000)
        }

        require(
            publicationCount == 0,
            "\(sampleCount) 帧应用拖动预览触发了 \(publicationCount) 次全局 Store 刷新"
        )

        let sorted = samples.sorted()
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let maximum = sorted.last ?? .infinity
        require(p95 < 0.35, "应用拖动预览 P95 超过 0.35ms：\(format(p95))ms")
        require(maximum < 3, "应用拖动预览峰值超过 3ms：\(format(maximum))ms")

        let resolveStart = DispatchTime.now().uptimeNanoseconds
        _ = store.resolvedAppMovePreview(app, to: finalPoint)
        let resolveEnd = DispatchTime.now().uptimeNanoseconds
        let releaseResolution = Double(resolveEnd - resolveStart) / 1_000_000
        require(
            releaseResolution < 40,
            "鼠标释放时的完整碰撞解析超过 40ms：\(format(releaseResolution))ms"
        )

        let originalPositions = Dictionary(
            uniqueKeysWithValues:
                store.assignedApps(in: group.id, includeHidden: false).map {
                    ($0.id, store.position(for: $0))
                }
        )
        var resizeSamples: [Double] = []
        resizeSamples.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let progress = CGFloat(index) / CGFloat(max(1, sampleCount - 1))
            let proposed = CGRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width + progress * 180,
                height: frame.height + progress * 120
            )
            let start = DispatchTime.now().uptimeNanoseconds
            _ = store.interactiveGroupResizePreview(
                id: group.id,
                proposedFrame: proposed,
                originalFrame: frame,
                originalAppPositions: originalPositions
            )
            let end = DispatchTime.now().uptimeNanoseconds
            resizeSamples.append(Double(end - start) / 1_000_000)
        }
        require(
            publicationCount == 0,
            "\(sampleCount) 帧分组尺寸预览触发了 \(publicationCount) 次全局 Store 刷新"
        )
        let sortedResize = resizeSamples.sorted()
        let resizeP95 = sortedResize[
            min(sortedResize.count - 1, Int(Double(sortedResize.count) * 0.95))
        ]
        let resizeMaximum = sortedResize.last ?? .infinity
        require(resizeP95 < 0.35, "分组尺寸预览 P95 超过 0.35ms：\(format(resizeP95))ms")
        require(resizeMaximum < 3, "分组尺寸预览峰值超过 3ms：\(format(resizeMaximum))ms")

        let viewport = CGSize(width: 1440, height: 900)
        var viewportSession = CanvasViewportInteractionSession(
            baseline: CanvasViewportTransform(
                scale: store.canvasScale,
                offset: store.canvasOffset
            )
        )
        var viewportSamples: [Double] = []
        viewportSamples.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let progress = CGFloat(index) / CGFloat(max(1, sampleCount - 1))
            let start = DispatchTime.now().uptimeNanoseconds
            viewportSession.translate(
                by: CGSize(
                    width: cos(progress * .pi * 12) * 0.8,
                    height: sin(progress * .pi * 12) * 0.8
                )
            )
            viewportSession.zoom(
                by: sin(progress * .pi * 24) * 0.004,
                around: CGPoint(
                    x: viewport.width * (0.25 + progress * 0.5),
                    y: viewport.height * 0.46
                ),
                in: viewport
            )
            _ = viewportSession.compositorOffset
            let end = DispatchTime.now().uptimeNanoseconds
            viewportSamples.append(Double(end - start) / 1_000_000)
        }
        require(
            publicationCount == 0,
            "\(sampleCount) 帧画布缩放/平移预览触发了 \(publicationCount) 次全局 Store 刷新"
        )
        let sortedViewport = viewportSamples.sorted()
        let viewportP95 = sortedViewport[
            min(sortedViewport.count - 1, Int(Double(sortedViewport.count) * 0.95))
        ]
        let viewportMaximum = sortedViewport.last ?? .infinity
        require(viewportP95 < 0.35, "画布缩放/平移预览 P95 超过 0.35ms：\(format(viewportP95))ms")
        require(viewportMaximum < 3, "画布缩放/平移预览峰值超过 3ms：\(format(viewportMaximum))ms")

        let publicationsBeforeCommit = publicationCount
        store.updateCanvas(
            offset: viewportSession.presentation.offset,
            scale: viewportSession.presentation.scale,
            persist: false
        )
        let commitPublications = publicationCount - publicationsBeforeCommit
        require(
            commitPublications == 1,
            "画布平移提交应只发布 1 次状态，实际为 \(commitPublications) 次"
        )

        withExtendedLifetime(publication) {}
        print(
            "空间拖动性能验收通过：\(sampleCount) 帧预览无全局刷新，"
                + "应用移动 P95 \(format(p95))ms，峰值 \(format(maximum))ms；"
                + "分组尺寸 P95 \(format(resizeP95))ms，峰值 \(format(resizeMaximum))ms；"
                + "画布缩放/平移 P95 \(format(viewportP95))ms，峰值 \(format(viewportMaximum))ms；"
                + "完整碰撞解析仅在释放时执行 \(format(releaseResolution))ms，"
                + "画布仅在交互结束时单次提交。"
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("空间拖动性能验收失败：\(message)\n".utf8))
        exit(1)
    }
}
