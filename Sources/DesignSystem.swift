import AppKit
import SwiftUI

// MARK: - Product palette

/// The single color boundary for the product. Group colors remain expressive;
/// the surrounding interface intentionally relies on semantic macOS colors.
enum Palette {
    static let accent = Color(red: 0.05, green: 0.47, blue: 0.98)
    static let windowFallback = Color(nsColor: .windowBackgroundColor)

    static func tint(for token: GroupTint) -> Color {
        switch token {
        case .blue: return Color(red: 0.12, green: 0.50, blue: 0.96)
        case .indigo: return Color(red: 0.38, green: 0.35, blue: 0.95)
        case .mint: return Color(red: 0.08, green: 0.69, blue: 0.50)
        case .pink: return Color(red: 0.96, green: 0.31, blue: 0.48)
        case .orange: return Color(red: 0.96, green: 0.58, blue: 0.12)
        case .teal: return Color(red: 0.08, green: 0.63, blue: 0.69)
        case .slate: return Color(red: 0.38, green: 0.43, blue: 0.52)
        case .purple: return Color(red: 0.63, green: 0.34, blue: 0.92)
        }
    }

    /// Selection is expressed as a glass highlight, never as text-colored
    /// chrome. Keep it white in both appearances while adapting intensity.
    static func selectedCardOutline(for colorScheme: ColorScheme) -> Color {
        Color.white.opacity(colorScheme == .dark ? 0.38 : 0.92)
    }
}

// MARK: - Layout and component metrics

enum ZizaiLayout {
    static let contentHorizontalPadding: CGFloat = 28
    static let contentTopPadding: CGFloat = 76
    static let contentBottomPadding: CGFloat = 40
    static let gridSpacing: CGFloat = 18
    static let sectionSpacing: CGFloat = 24
    static let cardPadding: CGFloat = 20
    static let modalPadding: CGFloat = 24
    static let panelPadding: CGFloat = 16
    /// Clear space from the tooltip arrow tip to its owning app icon. This is
    /// large enough for the tooltip's downward shadow to clear the artwork,
    /// while remaining inside the tightest supported grid row gap.
    static let appTooltipTargetGap: CGFloat = 8
}

enum ZizaiRadius {
    /// Large content containers such as group cards.
    static let card: CGFloat = 24
    /// Floating previews, search results, and inset information panels.
    static let panel: CGFloat = 18
    /// Compact interactive rows and hover backgrounds.
    static let control: CGFloat = 8
    /// Small badges and keyboard-key surfaces.
    static let badge: CGFloat = 6
    /// App-like square glyph containers.
    static let icon: CGFloat = 13

    static func canvasCard(scale: CGFloat) -> CGFloat {
        max(20, 30 * scale)
    }
}

enum TopChromeMetrics {
    static let controlHeight: CGFloat = 40
    static let tabContainerPadding: CGFloat = 4
    static let tabItemHeight: CGFloat = controlHeight - tabContainerPadding * 2
    static let actionButtonSize: CGFloat = controlHeight
    static let actionSymbolSize: CGFloat = 17
    static let verticalPadding: CGFloat = 8
    static let totalHeight: CGFloat = controlHeight + verticalPadding * 2
    /// Extends below the floating controls just far enough to turn hard
    /// viewport clipping into a gradual iOS-style material fade.
    static let contentFadeHeight: CGFloat = totalHeight + 42
    static let leadingPadding: CGFloat = 28
    static let trailingPadding: CGFloat = 18
    static let itemSpacing: CGFloat = 9
    static let brandHorizontalPadding: CGFloat = 12
    static let brandItemSpacing: CGFloat = 8
    /// Keeps the four-color mark supportive of the wordmark rather than
    /// visually dominating it inside the 40-point brand capsule.
    static let brandMarkSize: CGFloat = 22
    static let tabItemWidth: CGFloat = 84
    static let searchWidth: CGFloat = 304
}

// MARK: - Brand identity

/// The in-app brand mark is deliberately separate from `AppIcon.icon`.
/// Finder, Dock, Spotlight and App Store own the system icon's shape and glass
/// treatment; product chrome renders only the transparent four-color artwork,
/// with no background, border, material or shadow in either appearance.
struct ZizaiBrandMark: View {
    var size: CGFloat = TopChromeMetrics.brandMarkSize

    var body: some View {
        Image(nsImage: ZizaiBrandArtwork.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private enum ZizaiBrandArtwork {
    static let image: NSImage = {
        let resourceName = "BrandMarkForeground"
        if let image = Bundle.main.image(forResource: NSImage.Name(resourceName)) {
            return image
        }

        #if ZIZAI_VISUAL_AUDIT
            if let path = ProcessInfo.processInfo.environment["ZIZAI_BRAND_MARK_PATH"],
                let image = NSImage(contentsOfFile: path)
            {
                return image
            }
        #endif

        assertionFailure("Missing in-app brand artwork: \(resourceName).svg")
        return NSImage(size: NSSize(width: 1, height: 1))
    }()
}

/// One symbol treatment for every circular action in the floating top chrome.
/// The search control uses a smaller layout frame internally so its collapsed
/// glyph remains optically centered, but its color, point size and weight are
/// identical to the adjacent add and help actions.
struct ZizaiTopChromeActionSymbol: View {
    let systemName: String
    var frameWidth: CGFloat = TopChromeMetrics.actionButtonSize
    var frameHeight: CGFloat = TopChromeMetrics.actionButtonSize

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: TopChromeMetrics.actionSymbolSize, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: frameWidth, height: frameHeight)
    }
}

enum ZizaiControlMetrics {
    static let compactRowHeight: CGFloat = 30
    static let canvasBarItemHeight: CGFloat = 34
    static let canvasBarButtonSize: CGFloat = 32
    static let groupMenuButtonSize: CGFloat = 28
}

// MARK: - Motion

/// One motion language for the whole product. The curves are deliberately
/// non-bouncy: controls react immediately, then settle with a long, soft tail
/// instead of snapping or oscillating. Direct manipulation (dragging, panning
/// and live resizing) remains unanimated so the pointer always owns the frame.
@MainActor
enum ZizaiMotion {
    static let press = Animation.timingCurve(0.22, 0.78, 0.20, 1, duration: 0.11)
    static let hover = Animation.timingCurve(0.20, 0.82, 0.20, 1, duration: 0.16)
    static let control = Animation.timingCurve(0.18, 0.86, 0.20, 1, duration: 0.20)
    /// The search surface is one persistent control: its trailing edge stays
    /// anchored beside the other actions while the capsule grows to the left.
    /// A slightly longer tail makes that spatial change readable without
    /// introducing spring overshoot.
    static let searchExpansion = Animation.timingCurve(0.20, 0.88, 0.18, 1, duration: 0.30)
    static let searchDisclosure = Animation.timingCurve(0.22, 0.82, 0.20, 1, duration: 0.16)
    /// Results should answer typing immediately and never inherit the wider
    /// chrome expansion animation.
    static let searchContent = Animation.timingCurve(0.20, 0.82, 0.20, 1, duration: 0.16)
    static let selection = Animation.timingCurve(0.16, 0.90, 0.20, 1, duration: 0.24)
    static let feedback = Animation.timingCurve(0.18, 0.86, 0.20, 1, duration: 0.24)
    static let spatial = Animation.timingCurve(0.16, 0.92, 0.18, 1, duration: 0.32)

    static let controlTransition = AnyTransition.opacity.combined(
        with: .scale(scale: 0.985)
    )
    static let tooltipTransition = AnyTransition.opacity.combined(
        with: .scale(scale: 0.985, anchor: .bottom)
    )
    static let contentTransition = AnyTransition.opacity
    static let searchResultsTransition = AnyTransition.opacity
    static let toastTransition = AnyTransition.move(edge: .bottom).combined(with: .opacity)
    static let errorTransition = AnyTransition.move(edge: .top).combined(with: .opacity)
}

// MARK: - Typography

/// Text roles are intentionally few. Weight is reserved for hierarchy and
/// selection, instead of being repeated on every label.
enum ZizaiTypography {
    static let heroTitle = Font.system(size: 28, weight: .semibold)
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let sheetTitle = Font.system(size: 20, weight: .semibold)
    static let unavailableTitle = Font.system(size: 17, weight: .medium)
    static let groupTitle = Font.system(size: 16, weight: .medium)
    static let sectionTitle = Font.system(size: 15, weight: .medium)
    static let brandTitle = Font.system(size: 14, weight: .medium)
    static let rowTitle = Font.system(size: 14, weight: .medium)
    static let lead = Font.system(size: 14, weight: .regular)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let secondary = Font.system(size: 12, weight: .regular)
    static let secondaryMedium = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let tab = Font.system(size: 13, weight: .medium)
    static let selectedTab = Font.system(size: 13, weight: .semibold)

    static let primaryLabelOpacity: Double = 0.88

    static func appName(size: CGFloat, scale: CGFloat) -> Font {
        .system(size: max(11, size * 0.165) * scale, weight: .medium)
    }

}

// MARK: - Color and elevation roles

enum ZizaiOpacity {
    /// The system backdrop remains visible, while most of the surface follows
    /// the current semantic window color so labels cannot lose contrast merely
    /// because the desktop wallpaper behind the translucent window is bright
    /// or dark.
    static let windowGlassVeil: Double = 0.78
    static let cardGlassVeil: Double = 0.08
    static let panelFill: Double = 0.04
    static let tintedPanelFill: Double = 0.055
    static let quietTintFill: Double = 0.035
    static let hoverFill: Double = 0.08
    static let quietBorder: Double = 0.15
}

enum ZizaiShadow {
    static let glassOpacity: Double = 0.045
    static let glassRadius: CGFloat = 7
    static let glassY: CGFloat = 5
    static let glassHighlightTopOpacity: Double = 0.48
    static let glassHighlightBottomOpacity: Double = 0.06
    static let glassHighlightWidth: CGFloat = 0.8

    /// App artwork already contains its own lighting. Keep only a compact,
    /// downward cast shadow so the original icon stays clean and unchanged.
    static let iconOpacity: Double = 0.06
    static let iconRadiusScale: CGFloat = 0.035
    static let iconYScale: CGFloat = 0.075
    static let cardOpacity: Double = 0.055
    static let selectedCardOpacity: Double = 0.075
    static let dropTargetOpacity: Double = 0.12
    static let cardRadius: CGFloat = 20
    static let selectedCardRadius: CGFloat = 22
    static let cardY: CGFloat = 6
    static let floatingOpacity: Double = 0.16
    static let floatingRadius: CGFloat = 20
    static let floatingY: CGFloat = 8

    static let selectedOpacity: Double = 0.18
    static let selectedRadius: CGFloat = 14
    static let selectedY: CGFloat = 4
}
