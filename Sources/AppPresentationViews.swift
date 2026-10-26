import AppKit
import SwiftUI

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

struct ToastView: View {
    @EnvironmentObject private var store: LauncherStore
    let notice: ToastNotice
    @ObservedObject var layoutModeController: LayoutModeController

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
            .padding(.bottom, layoutModeController.selection == .space ? 82 : 22)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ErrorBanner: View {
    @EnvironmentObject private var store: LauncherStore
    let message: String
    @ObservedObject var layoutModeController: LayoutModeController

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
            .padding(.bottom, layoutModeController.selection == .space ? 84 : 24)
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
