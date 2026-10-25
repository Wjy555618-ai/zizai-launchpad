import AppKit
import XCTest

@testable import 自在启动台

final class InteractionGeometryTests: XCTestCase {
    func testCanvasSafeRectReservesTopAndBottomChrome() {
        let viewport = CGSize(width: 1_040, height: 680)
        let safeRect = CanvasViewportMetrics.safeRect(in: viewport)

        XCTAssertEqual(safeRect.minY, CanvasViewportMetrics.topInset)
        XCTAssertEqual(viewport.height - safeRect.maxY, CanvasViewportMetrics.bottomInset)
        XCTAssertGreaterThan(safeRect.width, 0)
        XCTAssertGreaterThan(safeRect.height, 0)
    }

    func testOverviewTransformFitsWideContentBelowTheFormerZoomFloor() {
        let viewport = CGSize(width: 1_360, height: 860)
        let contentBounds = CGRect(x: -2_800, y: -1_450, width: 6_000, height: 3_200)
        let transform = CanvasViewportMetrics.fittedTransform(
            for: contentBounds,
            in: viewport,
            minimumScale: CanvasViewportMetrics.minimumScale,
            maximumScale: CanvasViewportMetrics.overviewMaximumScale
        )
        let safeRect = CanvasViewportMetrics.safeRect(in: viewport)
        let fittedFrame = CanvasViewportMetrics.screenFrame(
            for: contentBounds,
            transform: transform,
            in: viewport
        )

        XCTAssertLessThan(transform.scale, 0.24)
        XCTAssertGreaterThan(transform.scale, CanvasViewportMetrics.minimumScale)
        XCTAssertGreaterThanOrEqual(fittedFrame.minX, safeRect.minX - 0.001)
        XCTAssertGreaterThanOrEqual(fittedFrame.minY, safeRect.minY - 0.001)
        XCTAssertLessThanOrEqual(fittedFrame.maxX, safeRect.maxX + 0.001)
        XCTAssertLessThanOrEqual(fittedFrame.maxY, safeRect.maxY + 0.001)
    }

    func testPointerAnchoredZoomKeepsWorldPointFixed() {
        let viewport = CGSize(width: 1_200, height: 800)
        let anchor = CGPoint(x: 930, y: 170)
        let oldOffset = CGSize(width: 140, height: -60)
        let oldScale: CGFloat = 0.52
        let newScale: CGFloat = 1.12
        let worldBefore = worldPoint(
            below: anchor,
            offset: oldOffset,
            scale: oldScale,
            viewport: viewport
        )
        let newOffset = InteractionGeometry.anchoredCanvasOffset(
            currentOffset: oldOffset,
            oldScale: oldScale,
            newScale: newScale,
            anchor: anchor,
            viewport: viewport
        )
        let worldAfter = worldPoint(
            below: anchor,
            offset: newOffset,
            scale: newScale,
            viewport: viewport
        )

        XCTAssertEqual(worldBefore.x, worldAfter.x, accuracy: 0.0001)
        XCTAssertEqual(worldBefore.y, worldAfter.y, accuracy: 0.0001)
    }

    func testGroupHeadersUseOneUnifiedVisibilityRule() {
        XCTAssertTrue(InteractionGeometry.showsUnifiedGroupHeaders(atScale: 1))
        XCTAssertFalse(InteractionGeometry.showsUnifiedGroupHeaders(atScale: 0.78))
    }

    func testReorderingDoesNotLoseOrDuplicateIdentifiers() {
        let source = ["a", "b", "c", "d"]
        let reordered = InteractionGeometry.reorderedIDs(
            source,
            movingID: "b",
            toInsertionIndex: 4
        )

        XCTAssertEqual(reordered, ["a", "c", "d", "b"])
        XCTAssertEqual(Set(reordered), Set(source))
    }

    func testDroppingOnAdjacentGroupAlwaysProducesObservableReorder() {
        let ids = ["a", "b", "c"]
        let frames = [
            AppDragGroupFrame(groupID: "a", frame: CGRect(x: 0, y: 0, width: 400, height: 180)),
            AppDragGroupFrame(groupID: "b", frame: CGRect(x: 0, y: 200, width: 400, height: 180)),
            AppDragGroupFrame(groupID: "c", frame: CGRect(x: 0, y: 400, width: 400, height: 180)),
        ]

        let movingDown = InteractionGeometry.groupInsertionIndex(
            at: CGPoint(x: 100, y: 220),
            groupFrames: frames,
            orderedGroupIDs: ids,
            movingGroupID: "a"
        )
        XCTAssertEqual(movingDown, 2)
        XCTAssertEqual(
            InteractionGeometry.reorderedIDs(ids, movingID: "a", toInsertionIndex: movingDown ?? 0),
            ["b", "a", "c"]
        )

        let movingUp = InteractionGeometry.groupInsertionIndex(
            at: CGPoint(x: 100, y: 160),
            groupFrames: frames,
            orderedGroupIDs: ids,
            movingGroupID: "b"
        )
        XCTAssertEqual(movingUp, 0)
        XCTAssertEqual(
            InteractionGeometry.reorderedIDs(ids, movingID: "b", toInsertionIndex: movingUp ?? 0),
            ["b", "a", "c"]
        )
    }

    func testGeometryHelpersClampUnsafeInputsAndDescribeVisibility() {
        XCTAssertEqual(
            InteractionGeometry.worldTranslation(
                fromScreen: CGSize(width: 30, height: -20),
                scale: 0
            ),
            CGSize(width: 3_000, height: -2_000)
        )
        XCTAssertTrue(
            InteractionGeometry.isVisibleInViewport(
                center: CGPoint(x: -12, y: 100),
                viewport: CGSize(width: 800, height: 600),
                margin: 16
            )
        )
        XCTAssertFalse(
            InteractionGeometry.isVisibleInViewport(
                center: CGPoint(x: -17, y: 100),
                viewport: CGSize(width: 800, height: 600),
                margin: 16
            )
        )
        XCTAssertEqual(
            InteractionGeometry.normalizedInsertionIndex(
                movingFrom: 1,
                proposed: 4,
                itemCount: 4
            ),
            3
        )
        XCTAssertEqual(
            InteractionGeometry.normalizedInsertionIndex(
                movingFrom: nil,
                proposed: -20,
                itemCount: 4
            ),
            0
        )
    }

    func testGroupSizingProducesEnoughCapacityAcrossCardinalityBands() {
        for count in [0, 1, 2, 5, 10, 17, 40] {
            let size = InteractionGeometry.fittedGroupSize(for: count)
            let frame = CGRect(origin: .zero, size: size)
            XCTAssertGreaterThanOrEqual(size.width, InteractionGeometry.minimumGroupWidth)
            XCTAssertGreaterThanOrEqual(size.height, InteractionGeometry.minimumGroupHeight)
            XCTAssertGreaterThanOrEqual(InteractionGeometry.capacity(of: frame), max(1, count))
        }
    }

    func testAppInsertionUsesCapturedRowsAndRejectsUnrelatedCardBackground() {
        let group = AppDragGroupFrame(
            groupID: "group",
            frame: CGRect(x: 0, y: 0, width: 600, height: 420)
        )
        let items = [
            AppDragItemFrame(
                appID: "a",
                groupID: "group",
                index: 0,
                frame: CGRect(x: 80, y: 100, width: 100, height: 100)
            ),
            AppDragItemFrame(
                appID: "b",
                groupID: "group",
                index: 1,
                frame: CGRect(x: 220, y: 100, width: 100, height: 100)
            ),
        ]

        XCTAssertEqual(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 210, y: 150),
                appFrames: items,
                groupFrames: [group],
                excluding: "moving"
            ),
            AppDragInsertion(groupID: "group", index: 1)
        )
        XCTAssertEqual(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 350, y: 150),
                appFrames: items,
                groupFrames: [group],
                excluding: "moving"
            ),
            AppDragInsertion(groupID: "group", index: 2)
        )
        XCTAssertEqual(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 250, y: 228),
                appFrames: items,
                groupFrames: [group],
                excluding: "moving"
            ),
            AppDragInsertion(groupID: "group", index: 1),
            "A release on the lower label edge must resolve to the visible tile row."
        )
        XCTAssertNil(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 500, y: 360),
                appFrames: items,
                groupFrames: [group],
                excluding: "moving"
            )
        )
        XCTAssertEqual(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 100, y: 100),
                appFrames: [],
                groupFrames: [group],
                excluding: "moving"
            ),
            AppDragInsertion(groupID: "group", index: 0)
        )

        XCTAssertEqual(
            InteractionGeometry.appInsertion(
                at: CGPoint(x: 250, y: 150),
                appFrames: items,
                groupFrames: [],
                excluding: "moving"
            ),
            AppDragInsertion(groupID: "group", index: 1),
            "A visible tile must remain an authoritative drop target while its lazy container geometry catches up."
        )
    }

    func testEveryResizeHandleHasAStableAccessibleActionAndGeometry() {
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        let translation = CGSize(width: 20, height: 30)
        let names = Set(ResizeHandle.allCases.map(\.accessibilityName))

        XCTAssertEqual(names.count, ResizeHandle.allCases.count)
        XCTAssertEqual(
            ResizeHandle.topLeft.resizedFrame(from: frame, translation: translation),
            CGRect(x: 120, y: 130, width: 480, height: 370)
        )
        XCTAssertEqual(
            ResizeHandle.bottomRight.resizedFrame(from: frame, translation: translation),
            CGRect(x: 100, y: 100, width: 520, height: 430)
        )
        if #available(macOS 15.0, *) {
            for handle in ResizeHandle.allCases {
                _ = handle.cursorPosition
            }
        }
    }

    func testSpatialEngineFindsAFreePositionWithoutCrossingGroupBounds() {
        let groupFrame = CGRect(x: -300, y: -250, width: 600, height: 500)
        let centerRect = SpatialLayoutEngine.appCenterRect(for: groupFrame)
        let occupied = [
            CGPoint(x: centerRect.minX, y: centerRect.minY),
            CGPoint(x: centerRect.midX, y: centerRect.minY),
        ]

        let result = SpatialLayoutEngine.closestAvailablePosition(
            proposed: CGPoint(x: -10_000, y: -10_000),
            inside: centerRect,
            occupied: occupied
        )

        guard let result else { return XCTFail("Expected an available position") }
        XCTAssertGreaterThanOrEqual(result.x, centerRect.minX)
        XCTAssertLessThanOrEqual(result.x, centerRect.maxX)
        XCTAssertGreaterThanOrEqual(result.y, centerRect.minY)
        XCTAssertLessThanOrEqual(result.y, centerRect.maxY)
        XCTAssertTrue(
            occupied.allSatisfy {
                abs(result.x - $0.x) >= InteractionGeometry.appCellWidth
                    || abs(result.y - $0.y) >= InteractionGeometry.appCellHeight
            }
        )
    }

    func testSpatialEngineSeparatesCollidingGroupsDeterministically() {
        let size = StoredSize(width: 420, height: 340)
        let groups = [
            UserGroup(
                id: "moving",
                name: "Moving",
                subtitle: "",
                tint: .blue,
                center: StoredPoint(x: 0, y: 0),
                size: size,
                isStarterGroup: false
            ),
            UserGroup(
                id: "fixed",
                name: "Fixed",
                subtitle: "",
                tint: .mint,
                center: StoredPoint(x: 500, y: 0),
                size: size,
                isStarterGroup: false
            ),
        ]

        let resolved = SpatialLayoutEngine.constrainedCenter(
            for: "moving",
            proposed: CGPoint(x: 500, y: 0),
            in: groups
        )
        let resolvedFrame = CGRect(
            x: resolved.x - size.width / 2,
            y: resolved.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        XCTAssertFalse(
            SpatialLayoutEngine.collides(
                resolvedFrame,
                excluding: "moving",
                in: groups
            )
        )
    }

    private func worldPoint(
        below anchor: CGPoint,
        offset: CGSize,
        scale: CGFloat,
        viewport: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (anchor.x - viewport.width / 2 - offset.width) / scale,
            y: (anchor.y - viewport.height / 2 - offset.height) / scale
        )
    }
}
