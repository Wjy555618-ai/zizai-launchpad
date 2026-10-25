import AppKit
import Foundation

struct AppDragItemFrame: Equatable {
    let appID: String
    let groupID: String
    let index: Int
    let frame: CGRect
}

struct AppDragGroupFrame: Equatable {
    let groupID: String
    let frame: CGRect
}

struct AppDragInsertion: Equatable {
    let groupID: String
    let index: Int
}

struct CanvasViewportTransform: Equatable {
    let scale: CGFloat
    let offset: CGSize
}

/// Automatic canvas navigation keeps content clear of the floating controls.
/// Manual panning may still move content beneath the non-interactive edge fade.
enum CanvasViewportMetrics {
    static let horizontalInset: CGFloat = 40
    static let topInset: CGFloat = 98
    static let bottomInset: CGFloat = 82
    static let minimumScale: CGFloat = 0.12
    static let maximumScale: CGFloat = 1.45
    static let focusedMinimumScale: CGFloat = 0.36
    static let focusedMaximumScale: CGFloat = 1.12
    static let overviewMaximumScale: CGFloat = 1

    static func safeRect(in viewport: CGSize) -> CGRect {
        CGRect(
            x: horizontalInset,
            y: topInset,
            width: max(1, viewport.width - horizontalInset * 2),
            height: max(1, viewport.height - topInset - bottomInset)
        )
    }

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(maximumScale, max(minimumScale, scale))
    }

    /// Produces one centered transform for automatic focus and overview
    /// operations. Keeping the math here prevents controls, Store commands and
    /// tests from drifting onto different definitions of the safe viewport.
    static func fittedTransform(
        for contentBounds: CGRect,
        in viewport: CGSize,
        minimumScale requestedMinimumScale: CGFloat,
        maximumScale requestedMaximumScale: CGFloat
    ) -> CanvasViewportTransform {
        let safeRect = safeRect(in: viewport)
        let minimumScale = max(0.01, min(requestedMinimumScale, requestedMaximumScale))
        let maximumScale = max(minimumScale, requestedMaximumScale)
        let fittedScale = min(
            safeRect.width / max(1, contentBounds.width),
            safeRect.height / max(1, contentBounds.height)
        )
        let scale = min(maximumScale, max(minimumScale, fittedScale))
        return CanvasViewportTransform(
            scale: scale,
            offset: CGSize(
                width: safeRect.midX - viewport.width / 2 - contentBounds.midX * scale,
                height: safeRect.midY - viewport.height / 2 - contentBounds.midY * scale
            )
        )
    }

    static func screenFrame(
        for worldFrame: CGRect,
        transform: CanvasViewportTransform,
        in viewport: CGSize
    ) -> CGRect {
        CGRect(
            x: viewport.width / 2 + transform.offset.width + worldFrame.minX * transform.scale,
            y: viewport.height / 2 + transform.offset.height + worldFrame.minY * transform.scale,
            width: worldFrame.width * transform.scale,
            height: worldFrame.height * transform.scale
        )
    }
}

enum InteractionGeometry {
    static let appCellWidth: CGFloat = 164
    static let appCellHeight: CGFloat = 158
    static let groupHorizontalInset: CGFloat = 48
    static let groupTopInset: CGFloat = 82
    static let groupBottomInset: CGFloat = 30
    static let minimumGroupWidth: CGFloat = 360
    static let minimumGroupHeight: CGFloat = 300
    static let minimumGroupHeaderScreenWidth: CGFloat = 300
    static let minimumGroupHeaderScreenHeight: CGFloat = 220
    static let groupHeaderMinimumContentGap: CGFloat = 10
    static let groupHeaderControlHeight: CGFloat = 28
    static func worldTranslation(fromScreen translation: CGSize, scale: CGFloat) -> CGSize {
        let safeScale = max(0.01, scale)
        return CGSize(
            width: translation.width / safeScale,
            height: translation.height / safeScale
        )
    }

    static func isVisibleInViewport(
        center: CGPoint,
        viewport: CGSize,
        margin: CGFloat
    ) -> Bool {
        let safeMargin = max(0, margin)
        return center.x >= -safeMargin
            && center.x <= viewport.width + safeMargin
            && center.y >= -safeMargin
            && center.y <= viewport.height + safeMargin
    }

    /// Returns the canvas offset that keeps the world point below `anchor`
    /// fixed on screen while the canvas scale changes.
    static func anchoredCanvasOffset(
        currentOffset: CGSize,
        oldScale: CGFloat,
        newScale: CGFloat,
        anchor: CGPoint,
        viewport: CGSize
    ) -> CGSize {
        let safeOldScale = max(0.01, oldScale)
        let safeNewScale = max(0.01, newScale)
        let viewportCenter = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let worldPoint = CGPoint(
            x: (anchor.x - viewportCenter.x - currentOffset.width) / safeOldScale,
            y: (anchor.y - viewportCenter.y - currentOffset.height) / safeOldScale
        )
        return CGSize(
            width: anchor.x - viewportCenter.x - worldPoint.x * safeNewScale,
            height: anchor.y - viewportCenter.y - worldPoint.y * safeNewScale
        )
    }

    /// Header visibility is a canvas-level presentation mode, not a per-card
    /// exception. Using the minimum supported card produces one deterministic
    /// decision for every group at the current zoom, so cards never mix title
    /// states or let header chrome collide with the first row of apps.
    static func showsUnifiedGroupHeaders(atScale scale: CGFloat) -> Bool {
        let safeScale = max(0.01, scale)
        return showsGroupHeader(
            forScreenSize: CGSize(
                width: minimumGroupWidth * safeScale,
                height: minimumGroupHeight * safeScale
            ),
            scale: safeScale
        )
    }

    static func showsGroupHeader(forScreenSize size: CGSize, scale: CGFloat) -> Bool {
        let safeScale = max(0.01, scale)
        let topPadding = max(14, 18 * safeScale)
        let availableTopInset = groupTopInset * safeScale
        let requiredTopInset =
            topPadding
            + groupHeaderControlHeight
            + groupHeaderMinimumContentGap
        return size.width >= minimumGroupHeaderScreenWidth
            && size.height >= minimumGroupHeaderScreenHeight
            && availableTopInset >= requiredTopInset
    }

    static func preferredColumnCount(for appCount: Int) -> Int {
        switch max(1, appCount) {
        case 1: return 1
        case 2...4: return 2
        case 5...9: return 3
        case 10...16: return 4
        default: return 5
        }
    }

    static func fittedGroupSize(for appCount: Int) -> CGSize {
        let count = max(1, appCount)
        let columns = preferredColumnCount(for: count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        return CGSize(
            width: max(
                minimumGroupWidth,
                CGFloat(columns) * appCellWidth + groupHorizontalInset * 2
            ),
            height: max(
                minimumGroupHeight,
                CGFloat(rows) * appCellHeight + groupTopInset + groupBottomInset
            )
        )
    }

    static func contentRect(for frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + groupHorizontalInset,
            y: frame.minY + groupTopInset,
            width: max(1, frame.width - groupHorizontalInset * 2),
            height: max(1, frame.height - groupTopInset - groupBottomInset)
        )
    }

    static func capacity(of frame: CGRect) -> Int {
        let content = contentRect(for: frame)
        let columns = max(1, Int(floor(content.width / appCellWidth)))
        let rows = max(1, Int(floor(content.height / appCellHeight)))
        return columns * rows
    }

    static func normalizedInsertionIndex(
        movingFrom sourceIndex: Int?,
        proposed destinationIndex: Int,
        itemCount: Int
    ) -> Int {
        let clamped = min(max(0, destinationIndex), max(0, itemCount))
        guard let sourceIndex, sourceIndex < clamped else { return clamped }
        return clamped - 1
    }

    static func reorderedIDs(
        _ ids: [String],
        movingID: String,
        toInsertionIndex insertionIndex: Int
    ) -> [String] {
        guard let oldIndex = ids.firstIndex(of: movingID) else { return ids }
        let destination = normalizedInsertionIndex(
            movingFrom: oldIndex,
            proposed: insertionIndex,
            itemCount: ids.count
        )
        guard destination != oldIndex else { return ids }

        var result = ids
        let moving = result.remove(at: oldIndex)
        result.insert(moving, at: min(max(0, destination), result.count))
        return result
    }

    /// Resolves a group drag against the immutable card geometry captured when
    /// the gesture began. Dropping directly on another card must always produce
    /// an observable reorder: an adjacent card's near edge would otherwise
    /// normalize back to the source position and make a natural title-to-title
    /// drag look broken. Empty space between cards keeps exact insertion
    /// semantics so users can still choose a precise boundary.
    static func groupInsertionIndex(
        at location: CGPoint,
        groupFrames: [AppDragGroupFrame],
        orderedGroupIDs: [String],
        movingGroupID: String
    ) -> Int? {
        guard let sourceIndex = orderedGroupIDs.firstIndex(of: movingGroupID) else {
            return nil
        }
        let framesByID = Dictionary(uniqueKeysWithValues: groupFrames.map { ($0.groupID, $0.frame) })
        let candidates = orderedGroupIDs.enumerated().compactMap {
            index, groupID -> (index: Int, groupID: String, frame: CGRect)? in
            guard groupID != movingGroupID, let frame = framesByID[groupID] else { return nil }
            return (index, groupID, frame)
        }
        guard !candidates.isEmpty else { return 0 }

        if let target = candidates.first(where: { $0.frame.contains(location) }) {
            let proposed = target.index + (location.y >= target.frame.midY ? 1 : 0)
            let normalized = normalizedInsertionIndex(
                movingFrom: sourceIndex,
                proposed: proposed,
                itemCount: orderedGroupIDs.count
            )
            if normalized == sourceIndex {
                return sourceIndex < target.index ? target.index + 1 : target.index
            }
            return proposed
        }
        if let next = candidates.first(where: { location.y < $0.frame.midY }) {
            return next.index
        }
        return orderedGroupIDs.count
    }

    /// Resolves a library drag against the geometry captured when dragging began.
    /// A non-empty group accepts only a nearby row/slot; unrelated card background
    /// is deliberately not treated as "append to the end".
    static func appInsertion(
        at location: CGPoint,
        appFrames: [AppDragItemFrame],
        groupFrames: [AppDragGroupFrame],
        excluding appID: String
    ) -> AppDragInsertion? {
        let eligibleItems = appFrames.filter { $0.appID != appID }
        // The application tile is the user's most precise drop target. Resolve
        // it before consulting the surrounding card: LazyVGrid and ScrollView
        // can update a container's geometry one layout pass later than its
        // visible children, but a pointer released on a visible tile must still
        // produce the same deterministic insertion.
        let directlyHitGroupID = eligibleItems.first(where: { $0.frame.contains(location) })?.groupID
        let destinationGroupID =
            directlyHitGroupID
            ?? groupFrames.first(where: { $0.frame.contains(location) })?.groupID
        guard let destinationGroupID else { return nil }

        let items =
            eligibleItems
            .filter { $0.groupID == destinationGroupID }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                if lhs.frame.midY != rhs.frame.midY { return lhs.frame.midY < rhs.frame.midY }
                return lhs.frame.midX < rhs.frame.midX
            }

        guard !items.isEmpty else {
            return AppDragInsertion(groupID: destinationGroupID, index: 0)
        }

        let rows = appRows(from: items)
        let rowCandidates = rows.compactMap { row -> (row: [AppDragItemFrame], distance: CGFloat)? in
            guard let first = row.first else { return nil }
            let minY = row.map(\.frame.minY).min() ?? first.frame.minY
            let maxY = row.map(\.frame.maxY).max() ?? first.frame.maxY
            let averageHeight = row.map(\.frame.height).reduce(0, +) / CGFloat(row.count)
            // The visible tile includes icon, primary label and optional
            // instance label. AppKit may resolve a drag destination to the
            // lower label baseline, a few points outside SwiftUI's latest
            // measured cell. Keep that intentional edge forgiving without
            // turning unrelated card background into an append target.
            let verticalTolerance = min(48, max(16, averageHeight * 0.35))
            guard location.y >= minY - verticalTolerance,
                location.y <= maxY + verticalTolerance
            else { return nil }
            let rowMidY = row.map(\.frame.midY).reduce(0, +) / CGFloat(row.count)
            return (row, abs(location.y - rowMidY))
        }

        guard let selectedRow = rowCandidates.min(by: { $0.distance < $1.distance })?.row,
            let first = selectedRow.first,
            let last = selectedRow.last
        else { return nil }

        let averageWidth = selectedRow.map(\.frame.width).reduce(0, +) / CGFloat(selectedRow.count)
        let horizontalTolerance = min(52, max(18, averageWidth * 0.32))
        guard location.x >= first.frame.minX - horizontalTolerance,
            location.x <= last.frame.maxX + horizontalTolerance
        else { return nil }

        if let next = selectedRow.first(where: { location.x < $0.frame.midX }) {
            return AppDragInsertion(groupID: destinationGroupID, index: next.index)
        }
        return AppDragInsertion(groupID: destinationGroupID, index: last.index + 1)
    }

    private static func appRows(from items: [AppDragItemFrame]) -> [[AppDragItemFrame]] {
        let verticalOrder = items.sorted {
            if $0.frame.midY != $1.frame.midY { return $0.frame.midY < $1.frame.midY }
            return $0.frame.midX < $1.frame.midX
        }
        var rows: [[AppDragItemFrame]] = []

        for item in verticalOrder {
            if let rowIndex = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                let tolerance = max(first.frame.height, item.frame.height) * 0.5
                return abs(first.frame.midY - item.frame.midY) <= tolerance
            }) {
                rows[rowIndex].append(item)
            } else {
                rows.append([item])
            }
        }

        return rows.map { $0.sorted { $0.frame.midX < $1.frame.midX } }
    }
}

enum ResizeHandle: CaseIterable, Hashable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    @available(macOS 15.0, *)
    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        }
    }

    var accessibilityName: String {
        switch self {
        case .top: return "上边缘"
        case .bottom: return "下边缘"
        case .left: return "左边缘"
        case .right: return "右边缘"
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        }
    }

    func resizedFrame(from frame: CGRect, translation: CGSize) -> CGRect {
        var result = frame
        switch self {
        case .left, .topLeft, .bottomLeft:
            result.origin.x += translation.width
            result.size.width -= translation.width
        case .right, .topRight, .bottomRight:
            result.size.width += translation.width
        default:
            break
        }
        switch self {
        case .top, .topLeft, .topRight:
            result.origin.y += translation.height
            result.size.height -= translation.height
        case .bottom, .bottomLeft, .bottomRight:
            result.size.height += translation.height
        default:
            break
        }
        return result
    }
}
