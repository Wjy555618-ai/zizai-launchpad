import AppKit
import SwiftUI

private struct PrimaryLayerIsActiveEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var primaryLayerIsActive: Bool {
        get { self[PrimaryLayerIsActiveEnvironmentKey.self] }
        set { self[PrimaryLayerIsActiveEnvironmentKey.self] = newValue }
    }
}

@MainActor
private final class PrimaryLayerActivity: ObservableObject {
    @Published var isActive = false
}

private struct PrimaryLayerRoot<Content: View>: View {
    let content: Content
    @ObservedObject var activity: PrimaryLayerActivity

    var body: some View {
        content.environment(\.primaryLayerIsActive, activity.isActive)
    }
}

@MainActor
protocol LayoutModeSelectionObserver: AnyObject {
    func layoutModeSelectionDidChange(_ selection: LayoutMode)
}

@MainActor
final class LayoutModeController: ObservableObject {
    @Published var selection: LayoutMode {
        didSet {
            guard selection != oldValue else { return }
            for observer in selectionObservers.allObjects {
                (observer as? any LayoutModeSelectionObserver)?
                    .layoutModeSelectionDidChange(selection)
            }
        }
    }

    private let selectionObservers = NSHashTable<AnyObject>.weakObjects()

    init(selection: LayoutMode) {
        self.selection = selection
    }

    func addSelectionObserver(_ observer: any LayoutModeSelectionObserver) {
        selectionObservers.add(observer)
    }
}

final class PrimaryLayerContainer<Content: View>: NSView, LayoutModeSelectionObserver {
    private let activity = PrimaryLayerActivity()
    private let hostingView: NSHostingView<PrimaryLayerRoot<Content>>
    private let mode: LayoutMode
    private(set) var revision: String
    private var colorScheme: ColorScheme
    private var visibilityState:
        (
            isActive: Bool,
            parkedOpacity: Double,
            usesLayerVisibility: Bool,
            followsSelection: Bool
        )?
    var acceptsInteraction = true

    init(
        content: Content,
        mode: LayoutMode,
        layoutModeController: LayoutModeController,
        revision: String,
        colorScheme: ColorScheme
    ) {
        hostingView = NSHostingView(
            rootView: PrimaryLayerRoot(content: content, activity: activity)
        )
        self.mode = mode
        self.revision = revision
        self.colorScheme = colorScheme
        super.init(frame: .zero)
        wantsLayer = true
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        layoutModeController.addSelectionObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateContent(
        _ content: Content,
        revision: String,
        colorScheme: ColorScheme
    ) {
        let contentChanged = self.revision != revision
        let appearanceChanged = self.colorScheme != colorScheme
        guard contentChanged || appearanceChanged else { return }

        self.revision = revision
        self.colorScheme = colorScheme
        hostingView.rootView = PrimaryLayerRoot(content: content, activity: activity)
        if appearanceChanged {
            synchronizeHostedAppearance()
        }
        hostingView.needsLayout = true
        hostingView.needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeHostedAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        synchronizeHostedAppearance()
        // Reinstalling the value-type root asks SwiftUI to resolve semantic
        // colors from the new native appearance without discarding the
        // persistent host or its page state.
        hostingView.rootView = hostingView.rootView
        hostingView.needsDisplay = true
    }

    private func synchronizeHostedAppearance() {
        hostingView.appearance = window?.effectiveAppearance ?? effectiveAppearance
    }

    func updateVisibility(
        isActive: Bool,
        parkedOpacity: Double,
        usesLayerVisibility: Bool,
        followsSelection: Bool
    ) {
        guard
            visibilityState?.isActive != isActive
                || visibilityState?.parkedOpacity != parkedOpacity
                || visibilityState?.usesLayerVisibility != usesLayerVisibility
                || visibilityState?.followsSelection != followsSelection
        else { return }
        visibilityState = (isActive, parkedOpacity, usesLayerVisibility, followsSelection)
        applyVisibility(
            isActive: isActive,
            parkedOpacity: parkedOpacity,
            usesLayerVisibility: usesLayerVisibility
        )
    }

    func layoutModeSelectionDidChange(_ selection: LayoutMode) {
        guard let visibilityState, visibilityState.followsSelection else { return }
        let isActive = selection == mode
        guard visibilityState.isActive != isActive else { return }
        self.visibilityState?.isActive = isActive
        applyVisibility(
            isActive: isActive,
            parkedOpacity: visibilityState.parkedOpacity,
            usesLayerVisibility: visibilityState.usesLayerVisibility
        )
    }

    private func applyVisibility(
        isActive: Bool,
        parkedOpacity: Double,
        usesLayerVisibility: Bool
    ) {
        acceptsInteraction = isActive
        if activity.isActive != isActive {
            // `updateNSView` runs inside SwiftUI's reconciliation pass. Publish
            // the page-activity boundary on the next main turn so descendants
            // can stop transient effects without mutating observable state from
            // inside that same pass. The interaction flag rejects stale queued
            // values when prewarm or rapid navigation changes again first.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.acceptsInteraction == isActive else { return }
                self.activity.isActive = isActive
            }
        }
        // Keep inactive hosts paintable only during the one-time prewarm. Once
        // parkedOpacity reaches zero, the lightweight outer layer is the
        // single source of truth for painting. The NSView remains mounted and
        // laid out, so revealing all-apps never invalidates its large SwiftUI
        // subtree. Interaction and AX exposure stop at this outer boundary.
        let isPaintablePrewarmLayer = !isActive && parkedOpacity > 0.0001
        let shouldHide = !isActive && !isPaintablePrewarmLayer
        if usesLayerVisibility {
            isHidden = false
            layer?.isHidden = shouldHide
        } else {
            // NSView.cacheDisplay intentionally bypasses Core Animation's
            // hidden-layer state. Off-screen release evidence therefore uses
            // the equivalent view boundary so it captures only the active page.
            layer?.isHidden = false
            isHidden = shouldHide
        }
        alphaValue = isPaintablePrewarmLayer ? parkedOpacity : 1
        setAccessibilityHidden(!isActive)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsInteraction else { return nil }
        return super.hitTest(point)
    }

    override func accessibilityChildren() -> [Any]? {
        guard acceptsInteraction else { return [] }
        return super.accessibilityChildren()
    }
}

/// Each expensive page owns a persistent NSHostingView. Tab selection updates
/// only this lightweight AppKit container, so hundreds of icon cells are not
/// re-diffed or re-laid out merely to change the selected segment.
struct PersistentPrimaryLayer<Content: View>: NSViewRepresentable {
    let mode: LayoutMode
    let layoutModeController: LayoutModeController
    let revision: String
    let isActive: Bool
    let parkedOpacity: Double
    let followsSelection: Bool
    let usesLayerVisibility: Bool
    let colorScheme: ColorScheme
    let content: Content

    func makeNSView(context: Context) -> PrimaryLayerContainer<Content> {
        PrimaryLayerContainer(
            content: content,
            mode: mode,
            layoutModeController: layoutModeController,
            revision: revision,
            colorScheme: colorScheme
        )
    }

    func updateNSView(_ nsView: PrimaryLayerContainer<Content>, context: Context) {
        nsView.updateContent(
            content,
            revision: revision,
            colorScheme: colorScheme
        )
        nsView.updateVisibility(
            isActive: isActive,
            parkedOpacity: parkedOpacity,
            usesLayerVisibility: usesLayerVisibility,
            followsSelection: followsSelection
        )
    }
}
