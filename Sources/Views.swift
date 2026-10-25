import AppKit
import SwiftUI

@MainActor
final class LayoutModeController: ObservableObject {
    @Published var selection: LayoutMode

    init(selection: LayoutMode) {
        self.selection = selection
    }
}

private final class PrimaryLayerContainer<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private(set) var revision: String
    private var colorScheme: ColorScheme
    var acceptsInteraction = true

    init(content: Content, revision: String, colorScheme: ColorScheme) {
        hostingView = NSHostingView(rootView: content)
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
        hostingView.rootView = content
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

    func updateVisibility(isActive: Bool, parkedOpacity: Double) {
        acceptsInteraction = isActive
        // Keep inactive hosts paintable only during the one-time prewarm.
        // SwiftUI flattens hosted descendants into the window accessibility
        // tree, so zero opacity and parent accessibility flags alone are not
        // sufficient: the parked host must be hidden after prewarm.
        hostingView.isHidden = !isActive && parkedOpacity <= 0.0001
        alphaValue = isActive ? 1 : parkedOpacity
        setAccessibilityHidden(!isActive)
        hostingView.setAccessibilityHidden(!isActive)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsInteraction else { return nil }
        return super.hitTest(point)
    }
}

/// Each expensive page owns a persistent NSHostingView. Tab selection updates
/// only this lightweight AppKit container, so hundreds of icon cells are not
/// re-diffed or re-laid out merely to change the selected segment.
private struct PersistentPrimaryLayer<Content: View>: NSViewRepresentable {
    let revision: String
    let isActive: Bool
    let parkedOpacity: Double
    let colorScheme: ColorScheme
    let content: Content

    func makeNSView(context: Context) -> PrimaryLayerContainer<Content> {
        PrimaryLayerContainer(
            content: content,
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
        nsView.updateVisibility(isActive: isActive, parkedOpacity: parkedOpacity)
    }
}

struct RootView: View {
    /// A non-zero, visually imperceptible value keeps parked layers eligible
    /// for their one-time launch prewarm. Once that pass finishes, fully hide
    /// parked layers so Core Animation does not blend three full-window icon
    /// surfaces during every tab switch or canvas frame.
    private var parkedLayerOpacity: Double { isPrewarmingContent ? 0.001 : 0 }

    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var layoutModeController: LayoutModeController

    @State private var aliasTarget: AppInfo?
    @State private var aliasDraft = ""
    @State private var groupDraft: GroupDraft?
    @State private var groupPendingDeletion: UserGroup?
    @State private var showHelp = false
    @State private var showWelcome = false
    @State private var isSearchPresented = false
    @State private var allAppsFilter: AllAppsFilter = .all
    @State private var isAllAppsOptionsPresented = false
    @State private var isPrewarmingContent = true
    @State private var didPrewarmContent = false
    @State private var prewarmLayoutMode: LayoutMode?
    @FocusState private var searchFocused: Bool

    private var reduceMotion: Bool {
        ZizaiAccessibilityPreferences.reduceMotion(systemValue: systemReduceMotion)
    }

    /// The visible layer is owned by the view so a click can swap the already
    /// mounted content on the current frame. The store remains the durable
    /// source of truth, but its persistence update is allowed to follow after
    /// the visual response instead of sitting in front of it.
    private var activeLayoutMode: LayoutMode {
        layoutModeController.selection
    }

    /// Prewarming is a rendering concern, not navigation state. Keeping its
    /// temporary page choice separate prevents launch-time rendering work from
    /// overwriting a real navigation update or racing view-composition tests.
    private var renderedLayoutMode: LayoutMode {
        prewarmLayoutMode ?? activeLayoutMode
    }

    var body: some View {
        ZStack(alignment: .top) {
            contentBackground

            ZStack {
                primaryContentLayers
                    .opacity(store.isSearching ? 0 : 1)
                    .allowsHitTesting(!store.isSearching)

                if store.isSearching {
                    SearchResultsView(
                        aliasTarget: $aliasTarget,
                        aliasDraft: $aliasDraft
                    )
                    .transition(ZizaiMotion.searchResultsTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .zizaiAnimation(ZizaiMotion.searchContent, value: store.isSearching)

            ZizaiTopContentFade()
                .frame(maxWidth: .infinity)
                .frame(height: TopChromeMetrics.contentFadeHeight)
                .ignoresSafeArea(edges: .top)
                .zIndex(80)

            if isSearchPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .onTapGesture(perform: resetSearch)
                    .accessibilityHidden(true)
                    .zIndex(90)
            }

            // Only the controls float above the content. There is deliberately no
            // full-width header surface, reserved row, material, divider, or shadow.
            topChrome
                .frame(height: TopChromeMetrics.totalHeight)
                .zIndex(100)

            if let toast = store.toast {
                ToastView(notice: toast, layoutMode: activeLayoutMode)
                    .transition(ZizaiMotion.toastTransition)
                    .zIndex(20)
            }

            if let message = store.errorMessage {
                ErrorBanner(message: message, layoutMode: activeLayoutMode)
                    .transition(ZizaiMotion.errorTransition)
                    .zIndex(30)
            }

            if isPrewarmingContent {
                contentBackground
                    .contentShape(Rectangle())
                    .zIndex(1_000)
                    .accessibilityHidden(true)
            }
        }
        .zizaiAnimation(ZizaiMotion.feedback, value: store.toast?.id)
        .zizaiAnimation(ZizaiMotion.feedback, value: store.errorMessage)
        .sheet(item: $aliasTarget) { app in
            AliasEditor(app: app, draft: $aliasDraft)
                .environmentObject(store)
        }
        .sheet(item: $groupDraft) { draft in
            GroupEditorSheet(draft: draft) { name, tint in
                if let groupID = draft.editingGroupID {
                    store.updateGroup(id: groupID, name: name, tint: tint)
                } else {
                    store.createGroup(name: name, tint: tint, center: draft.center)
                }
                groupDraft = nil
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet {
                store.completeWelcome()
                showWelcome = false
            }
        }
        .alert(
            "删除分组？",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { if !$0 { groupPendingDeletion = nil } }
            ),
            presenting: groupPendingDeletion
        ) { group in
            Button("取消", role: .cancel) { groupPendingDeletion = nil }
            Button("删除分组", role: .destructive) {
                groupPendingDeletion = nil
                store.deleteGroup(id: group.id)
            }
        } message: { group in
            Text("不会删除任何应用。“\(group.name)”中的应用会移到其他分组，并且可以撤销。")
        }
        .zizaiDismissAlertOnOutsideClick(
            isPresented: groupPendingDeletion != nil
        ) {
            groupPendingDeletion = nil
        }
        .onAppear {
            showWelcome = !store.state.hasSeenWelcome
            clearSearchFocus()
            if !store.isReloadingApps {
                prewarmContentLayers()
            }
        }
        .zizaiOnChange(of: store.isReloadingApps) { isReloading in
            if !isReloading {
                prewarmContentLayers()
            }
        }
        .zizaiOnChange(of: store.focusSearchToken) { _ in
            focusSearch()
        }
        .zizaiOnChange(of: store.searchText) { _ in
            if store.isSearching {
                setSearchPresented(true)
            }
            store.refreshSearchSelection()
        }
        .zizaiOnChange(of: store.newGroupToken) { _ in
            presentNewGroup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zizaiLayoutModeRequested)) { notification in
            guard let mode = notification.object as? LayoutMode else { return }
            activateLayoutMode(mode)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flushPendingPersistence()
        }
        .frame(minWidth: 1_040, minHeight: 680)
    }

    private var topChrome: some View {
        ZStack {
            ViewModeSwitcher(
                selection: Binding(
                    get: { activeLayoutMode },
                    set: { mode in
                        activateLayoutMode(mode)
                    }
                )
            )
            .opacity(isSearchPresented ? 0 : 1)
            .allowsHitTesting(!isSearchPresented)
            .accessibilityHidden(isSearchPresented)
            .zizaiAnimation(ZizaiMotion.searchDisclosure, value: isSearchPresented)

            HStack(spacing: 12) {
                brandCapsule

                Spacer(minLength: 320)

                HStack(spacing: TopChromeMetrics.itemSpacing) {
                    ExpandableSearchControl(
                        text: $store.searchText,
                        isExpanded: isSearchPresented,
                        isFocused: $searchFocused,
                        onOpen: focusSearch,
                        onClear: clearSearchKeepingFocus,
                        onClose: resetSearch,
                        onExit: handleSearchExit,
                        onSubmit: store.advanceSearchResult
                    )
                    .layoutPriority(1)

                    Button(action: presentNewGroup) {
                        ZizaiTopChromeActionSymbol(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .zizaiGlassCapsule(interactive: true)
                    .accessibilityLabel("新建分组")
                    .accessibilityHint("创建一个可以改名和调整大小的分组")
                    .accessibilityIdentifier(ZizaiAccessibilityID.newGroupButton)

                    if activeLayoutMode == .allApps {
                        AllAppsOptionsButton(
                            selection: $allAppsFilter,
                            isPresented: $isAllAppsOptionsPresented
                        )
                        .transition(ZizaiMotion.controlTransition)
                    }

                    Button {
                        isAllAppsOptionsPresented = false
                        resetSearch()
                        showHelp = true
                    } label: {
                        ZizaiTopChromeActionSymbol(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                    .zizaiGlassCapsule(interactive: true)
                    .accessibilityLabel("使用帮助")
                    .accessibilityIdentifier(ZizaiAccessibilityID.helpButton)
                }
            }
        }
        .padding(.leading, TopChromeMetrics.leadingPadding)
        .padding(.trailing, TopChromeMetrics.trailingPadding)
        .padding(.vertical, TopChromeMetrics.verticalPadding)
    }

    /// The brand is informational in the normal chrome and becomes a real
    /// semantic control only while it has an action: dismissing search. This
    /// keeps the visible surface unchanged while ensuring pointer input,
    /// VoiceOver and XCUITest all target the same control boundary.
    @ViewBuilder
    private var brandCapsule: some View {
        if isSearchPresented {
            Button(action: resetSearch) {
                brandCapsuleContent
            }
            .buttonStyle(.plain)
            .zizaiGlassCapsule(interactive: true)
            .contentShape(Capsule())
            .accessibilityLabel("关闭搜索")
            .accessibilityHint("返回当前视图")
            .accessibilityIdentifier(ZizaiAccessibilityID.brandCapsule)
        } else {
            brandCapsuleContent
                .zizaiGlassCapsule()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("自在启动台")
        }
    }

    private var brandCapsuleContent: some View {
        HStack(alignment: .center, spacing: TopChromeMetrics.brandItemSpacing) {
            ZizaiBrandMark()

            Text("自在启动台")
                .font(ZizaiTypography.brandTitle)
                .foregroundStyle(Color.primary.opacity(ZizaiTypography.primaryLabelOpacity))
        }
        .padding(.horizontal, TopChromeMetrics.brandHorizontalPadding)
        .frame(height: TopChromeMetrics.controlHeight, alignment: .center)
        .contentShape(Capsule())
    }

    private var contentBackground: some View {
        ZizaiWindowBackdrop()
    }

    /// Keep all three expensive pages mounted. Switching now changes only
    /// visibility, hit testing and accessibility exposure; it no longer
    /// destroys one icon grid and constructs another in the click path.
    private var primaryContentLayers: some View {
        ZStack {
            PersistentPrimaryLayer(
                revision: "groups",
                isActive: renderedLayoutMode == .groups,
                parkedOpacity: parkedLayerOpacity,
                colorScheme: colorScheme,
                content: GroupLibraryView(
                    aliasTarget: $aliasTarget,
                    aliasDraft: $aliasDraft,
                    onEditGroup: presentEditGroup,
                    onDeleteGroup: { groupPendingDeletion = $0 }
                )
                .environmentObject(store)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PersistentPrimaryLayer(
                revision: "space",
                isActive: renderedLayoutMode == .space,
                parkedOpacity: parkedLayerOpacity,
                colorScheme: colorScheme,
                content: SpaceCanvasView(
                    shouldCaptureInput: { layoutModeController.selection == .space },
                    aliasTarget: $aliasTarget,
                    aliasDraft: $aliasDraft,
                    onEditGroup: presentEditGroup,
                    onDeleteGroup: { groupPendingDeletion = $0 }
                )
                .environmentObject(store)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PersistentPrimaryLayer(
                revision: allAppsFilter.rawValue,
                isActive: renderedLayoutMode == .allApps,
                parkedOpacity: parkedLayerOpacity,
                colorScheme: colorScheme,
                content: AllAppsView(
                    aliasTarget: $aliasTarget,
                    aliasDraft: $aliasDraft,
                    filter: $allAppsFilter
                )
                .environmentObject(store)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func activateLayoutMode(_ mode: LayoutMode) {
        guard activeLayoutMode != mode else { return }
        isAllAppsOptionsPresented = false
        resetSearch()

        zizaiAnimate(ZizaiMotion.selection, reduceMotion: reduceMotion) {
            layoutModeController.selection = mode
        }
        clearSearchFocus()
        store.stageLayoutModePersistence(mode)
    }

    /// Pay the three pages' one-time Core Animation paint cost during the
    /// window's launch handoff, while a neutral backdrop covers the content.
    /// AppDelegate already waits briefly before presenting the window, so the
    /// user receives ready-to-switch layers instead of a cold first tab.
    private func prewarmContentLayers() {
        guard !didPrewarmContent else { return }
        didPrewarmContent = true
        let warmupModes = LayoutMode.allCases

        func advance(to index: Int) {
            guard index < warmupModes.count else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                    prewarmLayoutMode = nil
                    isPrewarmingContent = false
                }
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                prewarmLayoutMode = warmupModes[index]
            }
            DispatchQueue.main.async {
                for window in NSApp.windows {
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.contentView?.displayIfNeeded()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                    advance(to: index + 1)
                }
            }
        }

        advance(to: 0)
    }

    private func presentNewGroup() {
        isAllAppsOptionsPresented = false
        resetSearch()
        let scale = max(store.canvasScale, 0.01)
        let center = CGPoint(
            x: -store.canvasOffset.width / scale,
            y: -store.canvasOffset.height / scale
        )
        groupDraft = GroupDraft(editingGroupID: nil, name: "新分组", tint: .blue, center: center)
    }

    private func clearSearchFocus() {
        searchFocused = false
        DispatchQueue.main.async {
            searchFocused = false
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func focusSearch() {
        isAllAppsOptionsPresented = false
        setSearchPresented(true)
        // The field stays mounted in both states, so it can become first responder
        // on the next run-loop pass. Avoiding a second update halfway through the
        // reveal animation keeps the opening motion continuous.
        DispatchQueue.main.async {
            guard isSearchPresented else { return }
            searchFocused = true
        }
    }

    private func clearSearchKeepingFocus() {
        store.clearSearch()
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    /// Escape follows the native search-field rhythm: first clear a query,
    /// then release focus when the already-empty field receives Escape again.
    private func handleSearchExit() {
        if store.isSearching {
            clearSearchKeepingFocus()
        } else {
            resetSearch()
        }
    }

    private func resetSearch() {
        store.clearSearch()
        setSearchPresented(false)
        clearSearchFocus()
    }

    private func setSearchPresented(_ isPresented: Bool) {
        AppTooltipPanelController.shared.setPresentationEnabled(!isPresented)
        isSearchPresented = isPresented
    }

    private func presentEditGroup(_ group: UserGroup) {
        groupDraft = GroupDraft(
            editingGroupID: group.id,
            name: group.name,
            tint: group.tint,
            center: group.center.point
        )
    }

}

private struct ViewModeSwitcher: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: LayoutMode
    @Namespace private var selectionIndicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LayoutMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(selection == mode ? ZizaiTypography.selectedTab : ZizaiTypography.tab)
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .frame(width: TopChromeMetrics.tabItemWidth, height: TopChromeMetrics.tabItemHeight)
                        .contentShape(Capsule())
                        .background {
                            if selection == mode {
                                Capsule()
                                    .fill(selectedFill)
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                Color.white.opacity(colorScheme == .dark ? 0.16 : 0.72), lineWidth: 0.8)
                                    }
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.05), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "layout-mode-selection", in: selectionIndicator)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.rawValue)
                .accessibilityValue(selection == mode ? "selected" : "not-selected")
                .accessibilityHint(mode.usageDescription)
                .accessibilityIdentifier(ZizaiAccessibilityID.layoutMode(mode))
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(TopChromeMetrics.tabContainerPadding)
        .zizaiGlassCapsule(interactive: true)
        .zizaiAnimation(ZizaiMotion.selection, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视图")
    }

    private var selectedFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.08)
    }
}

struct GroupMoreMenuIcon: View {
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.primary.opacity(isHovered ? 0.58 : 0.42))
            .frame(width: ZizaiControlMetrics.groupMenuButtonSize, height: ZizaiControlMetrics.groupMenuButtonSize)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: ZizaiRadius.control, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.045 : 0))
            )
            .onHover { isHovered = $0 }
            .zizaiAnimation(ZizaiMotion.hover, value: isHovered)
    }
}

struct AppIconContent: View {
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    let size: CGFloat
    var showName = true
    var isHidden = false
    var isSelected = false
    var layoutScale: CGFloat = 1

    @State private var isDetailHovered = false
    @State private var tooltipAnchorID = UUID().uuidString

    var body: some View {
        let effectiveScale = max(0.01, layoutScale)
        let renderedSize = size * effectiveScale
        let detailText = store.instanceLabel(for: app) ?? app.purpose
        let icon = IconCache.shared.icon(for: app.path)

        VStack(spacing: 7 * effectiveScale) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: renderedSize, height: renderedSize)
                    .shadow(
                        color: .black.opacity(ZizaiShadow.iconOpacity),
                        radius: renderedSize * ZizaiShadow.iconRadiusScale,
                        y: renderedSize * ZizaiShadow.iconYScale
                    )

                if isHidden {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 9 * effectiveScale, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5 * effectiveScale)
                        .background(.black.opacity(0.62), in: Circle())
                        .offset(x: 5 * effectiveScale, y: -5 * effectiveScale)
                }
            }
            .frame(width: renderedSize, height: renderedSize)
            .background {
                AppTooltipWindowAnchor(
                    id: tooltipAnchorID,
                    text: detailText,
                    isPresented: isDetailHovered && !detailText.isEmpty
                )
            }

            if showName {
                VStack(spacing: 2 * effectiveScale) {
                    Text(store.editableDisplayName(for: app))
                        .font(ZizaiTypography.appName(size: size, scale: effectiveScale))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let instance = store.instanceLabel(for: app), effectiveScale >= 0.8 {
                        Text(instance)
                            .font(
                                .system(
                                    size: max(9, size * 0.135) * effectiveScale,
                                    weight: .regular
                                )
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(width: max(104, size * 1.72) * effectiveScale)
            }
        }
        .padding(8 * effectiveScale)
        .background(
            RoundedRectangle(cornerRadius: ZizaiRadius.panel * effectiveScale, style: .continuous)
                .fill(isSelected ? Palette.accent.opacity(0.12) : Color.clear)
        )
        .onHover { isDetailHovered = $0 }
        .zizaiAnimation(ZizaiMotion.hover, value: isDetailHovered)
        .accessibilityLabel(
            [store.displayName(for: app), store.instanceLabel(for: app)]
                .compactMap { $0 }
                .joined(separator: "，")
        )
        .accessibilityValue(detailText)
    }
}

struct AppTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .zizaiAnimation(ZizaiMotion.press, value: configuration.isPressed)
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 160, height: 160)
        icons[path] = image
        return image
    }

    #if DEBUG || ZIZAI_VISUAL_AUDIT
        /// Deterministic icon injection for isolated UI tests and render
        /// evidence. Release builds always resolve icons through NSWorkspace.
        func registerFixtureIcon(_ image: NSImage, for path: String) {
            image.size = NSSize(width: 160, height: 160)
            icons[path] = image
        }
    #endif

    func prewarm(paths: [String]) {
        for path in paths {
            _ = icon(for: path)
        }
    }

    /// NSWorkspace icon lookup is synchronous and AppKit-bound. Warm a small
    /// batch per main-actor turn so a large Applications folder cannot occupy
    /// one uninterrupted event-loop slice.
    func prewarmCooperatively(paths: [String], batchSize: Int = 1) async {
        let uniquePaths = Array(Set(paths)).sorted()
        let safeBatchSize = max(1, batchSize)
        for (index, path) in uniquePaths.enumerated() {
            guard !Task.isCancelled else { return }
            _ = icon(for: path)
            if (index + 1).isMultiple(of: safeBatchSize) {
                await Task.yield()
            }
        }
    }
}

private struct ToastView: View {
    @EnvironmentObject private var store: LauncherStore
    let notice: ToastNotice
    let layoutMode: LayoutMode

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(notice.message)
                    .font(ZizaiTypography.bodyMedium)
                if let actionTitle = notice.actionTitle {
                    Divider().frame(height: 17)
                    Button(actionTitle) { store.undoLastAction() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier(ZizaiAccessibilityID.toastUndo)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .zizaiGlassCapsule(interactive: true)
            .padding(.bottom, layoutMode == .space ? 82 : 22)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ErrorBanner: View {
    @EnvironmentObject private var store: LauncherStore
    let message: String
    let layoutMode: LayoutMode

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                Button("知道了") { store.errorMessage = nil }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .zizaiGlassCapsule()
            .padding(.bottom, layoutMode == .space ? 84 : 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("错误：\(message)")
    }
}

struct AliasEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    @Binding var draft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: IconCache.shared.icon(for: app.path))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置显示名称")
                        .font(ZizaiTypography.sheetTitle)
                    Text(app.name == app.chineseName ? "应用名称：\(app.name)" : "原名：\(app.name)")
                        .font(ZizaiTypography.secondary)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("例如：界面设计、AI 助手", text: $draft)
                .textFieldStyle(.roundedBorder)

            Text("只修改自在启动台中的显示名称，不会改变原应用。原名、用途和新名称都可以继续搜索。")
                .font(ZizaiTypography.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("恢复原名") {
                    store.setAlias("", for: app)
                    dismiss()
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    store.setAlias(draft, for: app)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(ZizaiLayout.modalPadding)
        .frame(width: 440)
        .zizaiDismissSheetOnOutsideClick {
            dismiss()
        }
    }
}
