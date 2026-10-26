import AppKit
import SwiftUI

struct RootView: View {
    private let performsLaunchPrewarm: Bool
    private let usesLayerVisibility: Bool
    private let onLaunchPrewarmCompleted: (() -> Void)?

    init(
        layoutModeController: LayoutModeController,
        performsLaunchPrewarm: Bool = true,
        usesLayerVisibility: Bool = true,
        onLaunchPrewarmCompleted: (() -> Void)? = nil
    ) {
        self.layoutModeController = layoutModeController
        self.performsLaunchPrewarm = performsLaunchPrewarm
        self.usesLayerVisibility = usesLayerVisibility
        self.onLaunchPrewarmCompleted = onLaunchPrewarmCompleted
        _isPrewarmingContent = State(initialValue: performsLaunchPrewarm)
        _didPrewarmContent = State(initialValue: !performsLaunchPrewarm)
    }

    /// A non-zero, visually imperceptible value keeps parked layers eligible
    /// for their one-time launch prewarm. Once that pass finishes, fully hide
    /// parked layers so Core Animation does not blend three full-window icon
    /// surfaces during every tab switch or canvas frame.
    private var parkedLayerOpacity: Double { isPrewarmingContent ? 0.001 : 0 }

    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let layoutModeController: LayoutModeController

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
                ToastView(
                    notice: toast,
                    layoutModeController: layoutModeController
                )
                .transition(ZizaiMotion.toastTransition)
                .zIndex(20)
            }

            if let message = store.errorMessage {
                ErrorBanner(
                    message: message,
                    layoutModeController: layoutModeController
                )
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
            if performsLaunchPrewarm && !store.isReloadingApps {
                prewarmContentLayers()
            }
        }
        .zizaiOnChange(of: store.isReloadingApps) { isReloading in
            if performsLaunchPrewarm && !isReloading {
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
            LayoutModeSwitcherHost(
                layoutModeController: layoutModeController,
                isAllAppsOptionsPresented: $isAllAppsOptionsPresented,
                reduceMotion: reduceMotion
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

                    AppCatalogOptionsHost(
                        selection: $allAppsFilter,
                        isPresented: $isAllAppsOptionsPresented,
                        onSelectFilter: { filter in
                            allAppsFilter = filter
                            activateLayoutMode(.allApps)
                        }
                    )

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
                mode: .groups,
                layoutModeController: layoutModeController,
                revision: "groups",
                isActive: renderedLayoutMode == .groups,
                parkedOpacity: parkedLayerOpacity,
                followsSelection: prewarmLayoutMode == nil,
                usesLayerVisibility: usesLayerVisibility,
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
                mode: .space,
                layoutModeController: layoutModeController,
                revision: "space",
                isActive: renderedLayoutMode == .space,
                parkedOpacity: parkedLayerOpacity,
                followsSelection: prewarmLayoutMode == nil,
                usesLayerVisibility: usesLayerVisibility,
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
                mode: .allApps,
                layoutModeController: layoutModeController,
                revision: allAppsFilter.rawValue,
                isActive: renderedLayoutMode == .allApps,
                parkedOpacity: parkedLayerOpacity,
                followsSelection: prewarmLayoutMode == nil,
                usesLayerVisibility: usesLayerVisibility,
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
                    DispatchQueue.main.async {
                        for window in NSApp.windows {
                            window.contentView?.layoutSubtreeIfNeeded()
                            window.contentView?.displayIfNeeded()
                        }
                        onLaunchPrewarmCompleted?()
                    }
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
