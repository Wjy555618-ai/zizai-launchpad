import AppKit
import SwiftUI

struct DockStyleTooltip: View {
    let text: String
    var tailX: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.86))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .background {
                ZStack {
                    DockTooltipMaterial()
                    Color(nsColor: .textBackgroundColor).opacity(0.76)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(ZizaiShadow.glassHighlightTopOpacity * 0.24),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(DockTooltipShape(tailX: tailX))
            }
            .overlay {
                DockTooltipShape(tailX: tailX)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(ZizaiShadow.glassHighlightTopOpacity),
                                Color.primary.opacity(ZizaiShadow.glassHighlightBottomOpacity),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            }
            .shadow(
                color: .black.opacity(ZizaiShadow.glassOpacity),
                radius: ZizaiShadow.glassRadius,
                y: ZizaiShadow.glassY
            )
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct DockTooltipMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .withinWindow
        nsView.state = .followsWindowActiveState
    }
}

struct DockTooltipShape: Shape {
    let tailX: CGFloat?

    func path(in rect: CGRect) -> Path {
        let tailHeight: CGFloat = 7
        let tailHalfWidth: CGFloat = 6
        let bubbleBottom = max(rect.minY, rect.maxY - tailHeight)
        let bubbleHeight = max(0, bubbleBottom - rect.minY)
        let cornerRadius = min(bubbleHeight / 2, rect.width / 2)
        let minimumTailCenter = rect.minX + cornerRadius + tailHalfWidth + 3
        let maximumTailCenter = rect.maxX - cornerRadius - tailHalfWidth - 3
        let preferredTailCenter = tailX.map { rect.minX + $0 } ?? rect.midX
        let tailCenter = min(max(preferredTailCenter, minimumTailCenter), maximumTailCenter)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bubbleBottom - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: bubbleBottom),
            control: CGPoint(x: rect.maxX, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: tailCenter + tailHalfWidth, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: tailCenter, y: rect.maxY),
            control: CGPoint(x: tailCenter + 3, y: bubbleBottom + 4)
        )
        path.addQuadCurve(
            to: CGPoint(x: tailCenter - tailHalfWidth, y: bubbleBottom),
            control: CGPoint(x: tailCenter - 3, y: bubbleBottom + 4)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: bubbleBottom - cornerRadius),
            control: CGPoint(x: rect.minX, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct AppInsertionMarker: View {
    var body: some View {
        Capsule()
            .fill(Palette.accent)
            .frame(width: 4, height: 96)
            .shadow(color: Palette.accent.opacity(0.35), radius: ZizaiRadius.badge)
            .accessibilityHidden(true)
    }
}
