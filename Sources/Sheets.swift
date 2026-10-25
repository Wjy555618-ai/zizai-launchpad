import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct GroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: GroupDraft
    let onSave: (String, GroupTint) -> Void

    @State private var name: String
    @State private var tint: GroupTint

    init(draft: GroupDraft, onSave: @escaping (String, GroupTint) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _tint = State(initialValue: draft.tint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: ZizaiRadius.icon, style: .continuous)
                        .fill(Palette.tint(for: tint).gradient)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.editingGroupID == nil ? "新建分组" : "编辑分组")
                        .font(ZizaiTypography.sheetTitle)
                        .accessibilityIdentifier(ZizaiAccessibilityID.groupEditorHeading)
                    Text("分组名称会同时用于空间、分组和搜索。")
                        .font(ZizaiTypography.secondary)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("名称")
                    .font(ZizaiTypography.secondaryMedium)
                    .foregroundStyle(.secondary)
                TextField("例如：每日工作、设计工具", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(ZizaiAccessibilityID.groupEditorNameField)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("识别色")
                    .font(ZizaiTypography.secondaryMedium)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(GroupTint.allCases) { item in
                        Button {
                            tint = item
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Palette.tint(for: item))
                                    .frame(width: 28, height: 28)
                                if tint == item {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("选择\(item.chineseName)")
                    }
                }
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(draft.editingGroupID == nil ? "创建" : "保存") {
                    onSave(name, tint)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.zizaiVisibleTrimmed.isEmpty)
            }
        }
        .padding(ZizaiLayout.modalPadding)
        .frame(width: 460)
        .zizaiDismissSheetOnOutsideClick {
            dismiss()
        }
    }
}

struct WelcomeSheet: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Palette.accent.gradient)
            }

            VStack(spacing: 7) {
                Text("一眼找到需要的应用")
                    .font(ZizaiTypography.heroTitle)
                Text("不用先学规则，直接开始使用。")
                    .font(ZizaiTypography.lead)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                WelcomeFeature(
                    icon: "square.grid.2x2.fill",
                    title: "先从分组开始",
                    detail: "应用自动对齐；拖动就能换序或换组。"
                )
                WelcomeFeature(
                    icon: "rectangle.3.group.fill",
                    title: "需要时再用空间",
                    detail: "自由摆放应用；分组可移动，也能从任意边缘缩放。"
                )
                WelcomeFeature(
                    icon: "magnifyingglass",
                    title: "不记名字也能找",
                    detail: "可按用途、中文别名、原名或分组搜索。"
                )
            }

            VStack(spacing: 8) {
                Button("立即开始") { onStart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Text("以后可以点右上角 ? 随时查看帮助")
                    .font(ZizaiTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(34)
        .frame(width: 720)
        .zizaiDismissSheetOnOutsideClick {
            onStart()
        }
    }
}

private struct WelcomeFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(ZizaiTypography.sectionTitle)
            Text(detail)
                .font(ZizaiTypography.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(17)
        .background(
            Color.primary.opacity(ZizaiOpacity.panelFill),
            in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
        )
    }
}

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacyPolicy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("使用帮助")
                            .font(ZizaiTypography.pageTitle)
                            .accessibilityIdentifier(ZizaiAccessibilityID.helpHeading)
                        Text("常用操作直接可见；右键菜单和拖动用于进阶整理。")
                            .font(ZizaiTypography.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                VStack(spacing: 0) {
                    HelpRow(icon: "square.grid.2x2", title: "分组", detail: "默认入口。拖动应用换序或换组；右键应用可移动、重命名或隐藏；拖动分组标题调整先后。")
                    Divider().padding(.leading, 46)
                    HelpRow(icon: "rectangle.3.group", title: "空间", detail: "拖动应用或分组自由摆放；拖动分组任意边缘缩放，空白处平移空间。")
                    Divider().padding(.leading, 46)
                    HelpRow(icon: "square.grid.3x3", title: "全部应用", detail: "查看全部已安装应用，并决定哪些入口显示在空间和分组中；不会修改或卸载原应用。")
                }
                .background(
                    Color.primary.opacity(ZizaiOpacity.panelFill),
                    in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                )

                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("快捷操作")
                            .font(ZizaiTypography.sectionTitle)
                        ShortcutRow(keys: "⌘ 1 / 2 / 3", action: "分组 / 空间 / 全部应用")
                        ShortcutRow(keys: "⌘ F", action: "搜索")
                        ShortcutRow(keys: "⌘ N", action: "新建分组")
                        ShortcutRow(keys: "⌘ 0", action: "适合全部内容")
                        ShortcutRow(keys: "⌘ R", action: "重新扫描应用")
                        ShortcutRow(keys: "⌘ Z", action: "撤销上一步")
                        ShortcutRow(keys: "方向键", action: "移动空间")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("安全与恢复")
                            .font(ZizaiTypography.sectionTitle)
                        Label("所有布局只保存在这台 Mac", systemImage: "lock.shield")
                        Label("移动、隐藏、改名都有撤销", systemImage: "arrow.uturn.backward")
                        Label("不会修改或卸载任何原应用", systemImage: "checkmark.shield")
                    }
                    .font(ZizaiTypography.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("隐私说明", systemImage: "hand.raised.fill")
                        .font(ZizaiTypography.sectionTitle)
                    Text("自在启动台不联网、不跟踪，也不收集、上传或共享个人数据。应用只读取“应用程序”目录中的应用名称、路径和图标；布局与界面偏好仅保存在本机沙盒中。")
                        .font(ZizaiTypography.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("不需要辅助功能、输入监控、相机、麦克风、照片、通讯录或定位权限。")
                        .font(ZizaiTypography.secondary)
                        .foregroundStyle(.secondary)
                    Button("查看完整隐私政策") {
                        showPrivacyPolicy = true
                    }
                }
                .padding(18)
                .background(
                    Palette.accent.opacity(ZizaiOpacity.tintedPanelFill),
                    in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                )
            }
            .padding(ZizaiLayout.modalPadding)
        }
        .frame(width: 650, height: 650)
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicySheet()
        }
        .zizaiDismissSheetOnOutsideClick {
            dismiss()
        }
    }
}

private struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("隐私政策")
                            .font(ZizaiTypography.pageTitle)
                        Text("更新日期：2026 年 8 月 22 日")
                            .font(ZizaiTypography.secondary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }

                PrivacySection(
                    title: "不收集个人数据",
                    detail: "自在启动台不收集、不上传、不出售、不共享任何个人数据，也不使用广告、分析、跟踪或第三方统计服务。"
                )
                PrivacySection(
                    title: "只读取应用目录",
                    detail: "应用只读取这台 Mac 上系统和用户“应用程序”目录中的应用名称、文件路径和图标，用于显示可启动的应用。这些信息不会离开你的设备。"
                )
                PrivacySection(
                    title: "设置只保存在本机",
                    detail:
                        "分组及顺序、中文别名、显示或隐藏状态、应用与分组的位置和尺寸、当前视图及画布位置与缩放、欢迎页完成状态，只保存在自在启动台自己的 App Sandbox 容器中。删除应用及其容器数据后，这些本地设置也会被删除。"
                )
                PrivacySection(
                    title: "不申请敏感权限",
                    detail: "自在启动台不需要网络、辅助功能、输入监控、相机、麦克风、照片、通讯录或定位权限。"
                )
            }
            .padding(ZizaiLayout.modalPadding)
        }
        .frame(width: 600, height: 520)
        .zizaiDismissSheetOnOutsideClick {
            dismiss()
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var applicationFolderAccess: ApplicationFolderAccess
    @State private var isChoosingApplicationFolder = false

    private let onApplicationSourcesChanged: () -> Void

    init(onApplicationSourcesChanged: @escaping () -> Void = {}) {
        self.onApplicationSourcesChanged = onApplicationSourcesChanged
    }

    var body: some View {
        Form {
            Section("启动") {
                Toggle(
                    "登录时在后台准备",
                    isOn: Binding(
                        get: { loginItemManager.isRequested },
                        set: { loginItemManager.setRequested($0) }
                    )
                )
                .accessibilityHint("默认关闭；开启后登录时静默准备，不弹窗、不占用程序坞，也不抢占焦点")

                statusContent
            }

            Section("应用来源") {
                LabeledContent("系统应用") {
                    Text("自动扫描")
                        .foregroundStyle(.secondary)
                }

                if let path = applicationFolderAccess.authorizedFolderPath {
                    LabeledContent("用户应用") {
                        Text(path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                    }

                    HStack(spacing: 10) {
                        Button("重新选择…") {
                            isChoosingApplicationFolder = true
                        }
                        Button("移除授权", role: .destructive) {
                            applicationFolderAccess.revokeAuthorization()
                            onApplicationSourcesChanged()
                        }
                    }
                } else {
                    Text("如果你在个人文件夹的“应用程序”中安装了应用，可选择该文件夹。自在启动台只会获得只读访问。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("选择用户应用程序文件夹…") {
                        isChoosingApplicationFolder = true
                    }
                    .accessibilityHint("通过系统选择器授予指定文件夹的持久只读访问")
                }

                if let errorMessage = applicationFolderAccess.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 390)
        .fileImporter(
            isPresented: $isChoosingApplicationFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let folder = urls.first else { return }
                if applicationFolderAccess.authorize(folder: folder) {
                    onApplicationSourcesChanged()
                }
            case .failure(let error):
                let cocoaError = error as NSError
                guard
                    cocoaError.domain != NSCocoaErrorDomain
                        || cocoaError.code != NSUserCancelledError
                else { return }
                applicationFolderAccess.reportSelectionError(error)
            }
        }
        .onAppear { loginItemManager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemManager.refresh()
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch loginItemManager.status {
        case .enabled:
            Label("已开启。下次登录后会在后台静默准备，不占用程序坞，点击应用时再显示窗口。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 8) {
                Label("还需要在系统设置中允许，当前尚未生效。", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Button("前往系统设置") { loginItemManager.openSystemSettings() }
            }
        case .notRegistered, .notFound:
            Text("默认关闭。只有你主动开启后，应用才会在登录时静默准备。")
                .foregroundStyle(.secondary)
        @unknown default:
            Text("登录项状态暂时不可用。")
                .foregroundStyle(.secondary)
        }

        if let errorMessage = loginItemManager.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PrivacySection: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ZizaiTypography.sectionTitle)
            Text(detail)
                .font(ZizaiTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ZizaiLayout.panelPadding)
        .background(
            Color.primary.opacity(ZizaiOpacity.panelFill),
            in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
        )
    }
}

private struct HelpRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(ZizaiTypography.rowTitle)
                Text(detail).font(ZizaiTypography.secondary).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: ZizaiRadius.badge))
            Text(action)
                .font(ZizaiTypography.secondary)
                .foregroundStyle(.secondary)
        }
    }
}
