import Foundation
import SwiftUI

enum ApplicationManagementPhase: Equatable {
    case inactive
    case entering
    case active
    case exiting
}

/// One source of truth for the complete application-management transition.
///
/// Entering and leaving management mode each use one finite SwiftUI chrome
/// transition. Continuous edit feedback is owned by a Core Animation layer;
/// `TimelineView` and repeating SwiftUI transforms remain forbidden because
/// they lay out every tile on every frame and starve modal-alert hit testing.
enum ApplicationManagementMotion {
    static let entryDuration: TimeInterval = 0.26
    static let exitDuration: TimeInterval = 0.22
    static let removalDuration: TimeInterval = 0.32
    static let reducedRemovalDuration: TimeInterval = 0.16
    static let removalScale: CGFloat = 0.82
    static let removalBlur: CGFloat = 3.5
    static let removalOffsetY: CGFloat = -6

    /// A subtle Launchpad-style edit signal rendered exclusively by Core
    /// Animation. The first and last values match so the compositor can loop
    /// without a visual jump.
    static let jiggleDuration: TimeInterval = 0.30
    static let jiggleRotationValues: [Double] = [
        -1.45 * .pi / 180,
        1.25 * .pi / 180,
        -1.45 * .pi / 180,
    ]
    static let jiggleTranslationValues: [Double] = [-0.7, 0.65, -0.7]

    static func jigglePhase(for identifier: String) -> TimeInterval {
        // Stable FNV-1a keeps neighboring icons out of phase across launches
        // without publishing per-frame SwiftUI state.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let fraction = Double(hash % 1_000) / 1_000
        return fraction * jiggleDuration
    }

    static func removalDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedRemovalDuration : removalDuration
    }

    @MainActor
    static func removalTransition(reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeOut(duration: reducedRemovalDuration)
        }
        return .timingCurve(0.32, 0.72, 0.18, 1, duration: removalDuration)
    }

    @MainActor
    static var removalReflow: Animation {
        .timingCurve(0.22, 0.78, 0.20, 1, duration: 0.24)
    }

    @MainActor
    static func chromeTransition(entering: Bool) -> Animation {
        Animation.timingCurve(
            0.22,
            0.78,
            0.20,
            1,
            duration: entering ? entryDuration : exitDuration
        )
    }
}

extension ApplicationManagementEndReason {
    var animatesVisualExit: Bool {
        switch self {
        case .explicit, .outsideInteraction, .inactivity:
            return true
        case .navigation, .lifecycle:
            return false
        }
    }
}
