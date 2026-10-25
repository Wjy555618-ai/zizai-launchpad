import CoreGraphics
import Foundation

enum SpatialMoveDirection: CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    func delta(step: CGFloat) -> CGSize {
        switch self {
        case .left:
            return CGSize(width: -step, height: 0)
        case .right:
            return CGSize(width: step, height: 0)
        case .up:
            return CGSize(width: 0, height: -step)
        case .down:
            return CGSize(width: 0, height: step)
        }
    }
}

/// Pure spatial rules shared by pointer interaction, accessibility actions,
/// migration, repair, and tests. This type deliberately owns no application
/// state: callers provide a complete snapshot and commit the returned values as
/// one undoable transaction.
enum SpatialLayoutEngine {
    static let groupGap: CGFloat = 42

    static func frame(for group: UserGroup) -> CGRect {
        CGRect(
            x: group.center.x - group.size.width / 2,
            y: group.center.y - group.size.height / 2,
            width: group.size.width,
            height: group.size.height
        )
    }

    static func appCenterRect(for groupFrame: CGRect) -> CGRect {
        let content = InteractionGeometry.contentRect(for: groupFrame)
        let insetX = min(
            InteractionGeometry.appCellWidth / 2,
            max(0, (content.width - 1) / 2)
        )
        let insetY = min(
            InteractionGeometry.appCellHeight / 2,
            max(0, (content.height - 1) / 2)
        )
        return content.insetBy(dx: insetX, dy: insetY)
    }

    static func nearestGroup(to point: CGPoint, in groups: [UserGroup]) -> UserGroup? {
        if let containing = groups.first(where: { frame(for: $0).contains(point) }) {
            return containing
        }
        return groups.min {
            distance($0.center.point, point) < distance($1.center.point, point)
        }
    }

    static func clamped(_ point: CGPoint, inside rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(rect.maxX, max(rect.minX, point.x)),
            y: min(rect.maxY, max(rect.minY, point.y))
        )
    }

    static func gridPosition(
        at index: Int,
        totalCount: Int,
        inside rect: CGRect
    ) -> CGPoint {
        let safeCount = max(totalCount, 1)
        let columns = max(1, Int(floor(rect.width / InteractionGeometry.appCellWidth)))
        let rows = max(1, Int(ceil(Double(safeCount) / Double(columns))))
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)
        return CGPoint(
            x: rect.minX + cellWidth * (CGFloat(max(0, index) % columns) + 0.5),
            y: rect.minY + cellHeight * (CGFloat(max(0, index) / columns) + 0.5)
        )
    }

    static func gridPositions(
        for itemIDs: [String],
        inside rect: CGRect
    ) -> [String: CGPoint] {
        Dictionary(
            uniqueKeysWithValues: itemIDs.enumerated().map { index, itemID in
                (
                    itemID,
                    gridPosition(at: index, totalCount: itemIDs.count, inside: rect)
                )
            }
        )
    }

    static func closestAvailablePosition(
        proposed: CGPoint,
        inside rect: CGRect,
        occupied: [CGPoint]
    ) -> CGPoint? {
        let clamped = clamped(proposed, inside: rect)

        func isAvailable(_ point: CGPoint) -> Bool {
            guard containsClosed(point, in: rect) else { return false }
            return occupied.allSatisfy { other in
                abs(point.x - other.x) >= InteractionGeometry.appCellWidth
                    || abs(point.y - other.y) >= InteractionGeometry.appCellHeight
            }
        }

        if isAvailable(clamped) { return clamped }

        let step: CGFloat = 18
        var candidates: [CGPoint] = []
        var y = rect.minY
        while y <= rect.maxY {
            var x = rect.minX
            while x <= rect.maxX {
                candidates.append(CGPoint(x: x, y: y))
                x += step
            }
            y += step
        }
        candidates.append(contentsOf: gridCandidatePositions(inside: rect))
        return
            candidates
            .sorted { distance($0, clamped) < distance($1, clamped) }
            .first(where: isAvailable)
    }

    static func needsRepair(_ positions: [String: CGPoint], inside rect: CGRect) -> Bool {
        let values = Array(positions.values)
        guard values.allSatisfy({ containsClosed($0, in: rect) }) else { return true }
        for left in values.indices {
            for right in values.indices where right > left {
                if abs(values[left].x - values[right].x) < InteractionGeometry.appCellWidth,
                    abs(values[left].y - values[right].y) < InteractionGeometry.appCellHeight
                {
                    return true
                }
            }
        }
        return false
    }

    static func mappedPositions(
        _ positions: [String: CGPoint],
        from oldRect: CGRect,
        to newRect: CGRect
    ) -> [String: CGPoint] {
        guard oldRect.width > 0, oldRect.height > 0 else { return positions }
        return positions.mapValues { point in
            let x = (point.x - oldRect.minX) / oldRect.width
            let y = (point.y - oldRect.minY) / oldRect.height
            return CGPoint(
                x: newRect.minX + min(1, max(0, x)) * newRect.width,
                y: newRect.minY + min(1, max(0, y)) * newRect.height
            )
        }
    }

    static func constrainedCenter(
        for groupID: String,
        proposed: CGPoint,
        in groups: [UserGroup]
    ) -> CGPoint {
        guard let group = groups.first(where: { $0.id == groupID }) else { return proposed }
        let size = group.size.size
        let protectedFrames =
            groups
            .filter { $0.id != groupID }
            .map { frame(for: $0).insetBy(dx: -groupGap, dy: -groupGap) }

        func candidateFrame(at center: CGPoint) -> CGRect {
            CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        func isAvailable(_ center: CGPoint) -> Bool {
            let candidate = candidateFrame(at: center)
            return protectedFrames.allSatisfy { !candidate.intersects($0) }
        }

        if isAvailable(proposed) { return proposed }

        var candidates: [CGPoint] = [proposed]
        for protected in protectedFrames {
            let left = protected.minX - size.width / 2
            let right = protected.maxX + size.width / 2
            let top = protected.minY - size.height / 2
            let bottom = protected.maxY + size.height / 2
            let yValues = [proposed.y, protected.midY, top, bottom]
            let xValues = [proposed.x, protected.midX, left, right]
            candidates.append(
                contentsOf: yValues.flatMap { y in
                    [CGPoint(x: left, y: y), CGPoint(x: right, y: y)]
                }
            )
            candidates.append(
                contentsOf: xValues.flatMap { x in
                    [CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)]
                }
            )
        }
        if let nearest =
            candidates
            .sorted(by: { distance($0, proposed) < distance($1, proposed) })
            .first(where: isAvailable)
        {
            return nearest
        }

        let step: CGFloat = 72
        for ring in 1...60 {
            let radius = CGFloat(ring) * step
            let samples = max(16, ring * 12)
            for sample in 0..<samples {
                let angle = CGFloat(sample) / CGFloat(samples) * .pi * 2
                let candidate = CGPoint(
                    x: proposed.x + cos(angle) * radius,
                    y: proposed.y + sin(angle) * radius
                )
                if isAvailable(candidate) { return candidate }
            }
        }

        guard let minimumX = protectedFrames.map(\.minX).min(),
            let maximumX = protectedFrames.map(\.maxX).max()
        else { return proposed }
        let leftFallback = CGPoint(x: minimumX - size.width / 2 - 1, y: proposed.y)
        let rightFallback = CGPoint(x: maximumX + size.width / 2 + 1, y: proposed.y)
        return distance(leftFallback, proposed) <= distance(rightFallback, proposed)
            ? leftFallback
            : rightFallback
    }

    static func collides(
        _ candidateFrame: CGRect,
        excluding groupID: String,
        in groups: [UserGroup]
    ) -> Bool {
        groups.contains { group in
            group.id != groupID
                && candidateFrame.intersects(
                    frame(for: group).insetBy(dx: -groupGap, dy: -groupGap)
                )
        }
    }

    private static func containsClosed(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func gridCandidatePositions(inside rect: CGRect) -> [CGPoint] {
        let columns = max(1, Int(floor(rect.width / InteractionGeometry.appCellWidth)))
        let rows = max(1, Int(floor(rect.height / InteractionGeometry.appCellHeight)))
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)
        return (0..<(columns * rows)).map { index in
            CGPoint(
                x: rect.minX + cellWidth * (CGFloat(index % columns) + 0.5),
                y: rect.minY + cellHeight * (CGFloat(index / columns) + 0.5)
            )
        }
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
