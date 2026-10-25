import AppKit
import SwiftUI

#if os(macOS)
    @MainActor
    enum RootWindowMaterial {
        static func install(in window: NSWindow) {
            guard let hostedContent = window.contentView,
                !(hostedContent is NSVisualEffectView)
            else { return }

            let material = NSVisualEffectView()
            material.appearance = window.appearance
            material.material = .sidebar
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            material.addSubview(hostedContent)
            hostedContent.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostedContent.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                hostedContent.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                hostedContent.topAnchor.constraint(equalTo: material.topAnchor),
                hostedContent.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            window.contentView = material
        }
    }
#endif

enum ZizaiAccessibilityPreferences {
    static func reduceMotion(systemValue: Bool) -> Bool {
        #if ZIZAI_VISUAL_AUDIT
            systemValue || ProcessInfo.processInfo.environment["ZIZAI_FORCE_REDUCED_EFFECTS"] == "1"
        #else
            systemValue
        #endif
    }

    static func reduceTransparency(systemValue: Bool) -> Bool {
        #if ZIZAI_VISUAL_AUDIT
            systemValue || ProcessInfo.processInfo.environment["ZIZAI_FORCE_REDUCED_EFFECTS"] == "1"
        #else
            systemValue
        #endif
    }
}

/// The actual blur is installed once at the NSWindow content-view boundary.
/// A semantic veil keeps foreground contrast tied to Aqua/Dark Aqua even when
/// a high-contrast wallpaper is visible through the system material.
struct ZizaiWindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private var reduceTransparency: Bool {
        ZizaiAccessibilityPreferences.reduceTransparency(systemValue: systemReduceTransparency)
    }

    var body: some View {
        Group {
            if reduceTransparency {
                Palette.windowFallback
            } else {
                Palette.windowFallback.opacity(ZizaiOpacity.windowGlassVeil)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A non-interactive material veil at the viewport edge. It does not reserve
/// layout space or paint an opaque toolbar; content continues underneath and
/// is progressively blurred/faded before it reaches the window boundary.
struct ZizaiTopContentFade: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        ZizaiAccessibilityPreferences.reduceTransparency(systemValue: systemReduceTransparency)
    }

    var body: some View {
        // Follow the active appearance so the floating controls retain their
        // contrast. The dark peak stays deliberately light enough that this
        // reads as a fade, never as a second toolbar surface.
        let edgeColor = colorScheme == .dark ? Color.black : Color.white
        let peakOpacity = reduceTransparency ? 1 : (colorScheme == .dark ? 0.28 : 0.54)

        LinearGradient(
            stops: [
                .init(color: edgeColor.opacity(peakOpacity), location: 0),
                .init(color: edgeColor.opacity(peakOpacity * 0.68), location: 0.42),
                .init(color: edgeColor.opacity(peakOpacity * 0.22), location: 0.80),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One visual compatibility boundary for the entire product.
///
/// macOS 26 receives the system Liquid Glass implementation. Earlier supported
/// systems keep the same capsule hierarchy and hit targets with a native
/// material surface instead of maintaining a second UI.
extension View {
    @ViewBuilder
    func zizaiGlassCapsule(interactive: Bool = false) -> some View {
        #if ZIZAI_VISUAL_AUDIT
            self.modifier(ZizaiAuditGlassCapsuleModifier())
        #else
            if #available(macOS 26.0, *) {
                if interactive {
                    self
                        .glassEffect(.clear.interactive(), in: .capsule)
                        .zizaiGlassLighting()
                } else {
                    self
                        .glassEffect(.clear, in: .capsule)
                        .zizaiGlassLighting()
                }
            } else {
                self
                    .background(.ultraThinMaterial, in: Capsule())
                    .zizaiGlassLighting()
            }
        #endif
    }

    /// A single light model for every floating top control: a restrained
    /// highlight from above and a soft shadow that falls below the surface.
    private func zizaiGlassLighting() -> some View {
        self
            .overlay {
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(ZizaiShadow.glassHighlightTopOpacity),
                                Color.white.opacity(ZizaiShadow.glassHighlightBottomOpacity),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: ZizaiShadow.glassHighlightWidth
                    )
            }
            .shadow(
                color: .black.opacity(ZizaiShadow.glassOpacity),
                radius: ZizaiShadow.glassRadius,
                y: ZizaiShadow.glassY
            )
    }

    /// Uses the modern two-value callback where it exists while retaining the
    /// pre-macOS 14 callback on older supported systems.
    @ViewBuilder
    func zizaiOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }

    /// Gives non-destructive sheets the transient dismissal behavior used by
    /// the rest of the interface. AppKit sheets normally keep the parent
    /// window modal until a button is pressed; this local event monitor treats
    /// a click in the parent window as cancel/close while leaving every click
    /// inside the sheet untouched.
    func zizaiDismissSheetOnOutsideClick(
        perform action: @escaping @MainActor () -> Void
    ) -> some View {
        background(
            ZizaiSheetOutsideClickMonitor(onOutsideClick: action)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    /// Applies the same outside-click-as-cancel rule to a system alert without
    /// replacing its native appearance or weakening its destructive action.
    /// The action is called only for a click outside the alert window.
    func zizaiDismissAlertOnOutsideClick(
        isPresented: Bool,
        perform action: @escaping @MainActor () -> Void
    ) -> some View {
        background(
            ZizaiAlertOutsideClickMonitor(
                isPresented: isPresented,
                onOutsideClick: action
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
    }

    /// Applies the shared motion curve while honoring Reduce Motion at the
    /// component boundary, so individual views cannot forget accessibility.
    func zizaiAnimation<Value: Equatable>(
        _ animation: Animation,
        value: Value
    ) -> some View {
        modifier(ZizaiAnimationModifier(animation: animation, value: value))
    }
}

#if ZIZAI_VISUAL_AUDIT
    /// System Liquid Glass is composited by the window server and is not
    /// captured faithfully by `cacheDisplay` in an off-screen audit window.
    /// The audit build uses deterministic semantic colors while production
    /// continues to use the native material above.
    private struct ZizaiAuditGlassCapsuleModifier: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            content
                .background(
                    colorScheme == .dark
                        ? Color(nsColor: .controlBackgroundColor).opacity(0.96)
                        : Color.white.opacity(0.94),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.24)
                                : Color.black.opacity(0.08),
                            lineWidth: 0.8
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 7, y: 4)
        }
    }
#endif

private struct ZizaiSheetOutsideClickMonitor: NSViewRepresentable {
    let onOutsideClick: @MainActor () -> Void

    func makeNSView(context: Context) -> ZizaiSheetOutsideClickMonitoringView {
        let view = ZizaiSheetOutsideClickMonitoringView()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(
        _ nsView: ZizaiSheetOutsideClickMonitoringView,
        context: Context
    ) {
        nsView.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(
        _ nsView: ZizaiSheetOutsideClickMonitoringView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}

@MainActor
private final class ZizaiSheetOutsideClickMonitoringView: NSView {
    var onOutsideClick: (@MainActor () -> Void)?

    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func startMonitoringIfNeeded() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard
                let self,
                let presentationWindow = self.window,
                presentationWindow.attachedSheet == nil,
                NSApp.keyWindow === presentationWindow
            else {
                return event
            }

            // A click delivered to the sheet belongs to its controls. A click
            // delivered to any other application window is outside the sheet
            // and should perform the sheet's cancel action.
            guard event.window !== presentationWindow else { return event }
            let action = self.onOutsideClick
            DispatchQueue.main.async {
                action?()
            }
            return nil
        }
    }
}

private struct ZizaiAlertOutsideClickMonitor: NSViewRepresentable {
    let isPresented: Bool
    let onOutsideClick: @MainActor () -> Void

    func makeNSView(context: Context) -> ZizaiAlertOutsideClickMonitoringView {
        let view = ZizaiAlertOutsideClickMonitoringView()
        view.isPresented = isPresented
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(
        _ nsView: ZizaiAlertOutsideClickMonitoringView,
        context: Context
    ) {
        nsView.isPresented = isPresented
        nsView.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(
        _ nsView: ZizaiAlertOutsideClickMonitoringView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}

@MainActor
private final class ZizaiAlertOutsideClickMonitoringView: NSView {
    var isPresented = false
    var onOutsideClick: (@MainActor () -> Void)?

    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoringIfNeeded()
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func startMonitoringIfNeeded() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard
                let self,
                self.isPresented,
                let parentWindow = self.window,
                let alertWindow = parentWindow.attachedSheet,
                NSApp.keyWindow === alertWindow
            else {
                return event
            }

            guard event.window !== alertWindow else { return event }
            let action = self.onOutsideClick
            DispatchQueue.main.async {
                action?()
            }
            return nil
        }
    }
}

private struct ZizaiAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let animation: Animation
    let value: Value

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

/// Imperative counterpart to `zizaiAnimation`. Use it for scrolling, focus
/// changes and discrete canvas commands; direct pointer manipulation stays in
/// explicit no-animation transactions.
@MainActor
func zizaiAnimate(
    _ animation: Animation,
    reduceMotion: Bool,
    updates: () -> Void
) {
    if reduceMotion {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    } else {
        withAnimation(animation, updates)
    }
}

/// A macOS 13-compatible empty state with the same information hierarchy as
/// ContentUnavailableView, which only exists from macOS 14.
struct ZizaiUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(ZizaiTypography.unavailableTitle)

            Text(description)
                .font(ZizaiTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}
