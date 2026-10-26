import AppKit
import SwiftUI

struct LibraryAppTile: View {
    @EnvironmentObject private var store: LauncherStore
    let app: AppInfo
    let groupID: String
    let index: Int
    @Binding var aliasTarget: AppInfo?
    @Binding var aliasDraft: String
    let onDragChanged: (AppInfo, String, Int, CGPoint) -> Void
    let onDragEnded: (AppInfo, CGPoint) -> Void
    @State private var suppressLaunch = false

    var body: some View {
        Button {
            if !suppressLaunch { store.launch(app) }
        } label: {
            AppIconContent(app: app, size: 64)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous))
        // A library tile has two mutually exclusive pointer meanings: a click
        // launches, while movement reorganizes. Give the drag recognizer
        // priority over Button's press recognizer so AppKit delivers the full
        // pointer sequence to one owner; the minimum distance preserves clicks.
        .simultaneousGesture(appDragGesture)
        .contextMenu {
            appMenu
        }
        .accessibilityLabel(store.displayName(for: app))
        .accessibilityValue(
            "当前分组：\(store.group(withID: groupID)?.name ?? "未知")，第 \(index + 1) 个，\(app.purpose)"
        )
        .accessibilityHint("单击打开；拖到应用之间可以插入换序，拖到其他分组可以换组")
        .accessibilityIdentifier(ZizaiAccessibilityID.appTile(app.id))
    }

    private var appDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("library"))
            .onChanged { value in
                suppressLaunch = true
                onDragChanged(app, groupID, index, value.location)
            }
            .onEnded { value in
                onDragEnded(app, value.location)
                DispatchQueue.main.async {
                    suppressLaunch = false
                }
            }
    }

    @ViewBuilder
    private var appMenu: some View {
        let orderedApps = store.apps(in: groupID)
        let index = orderedApps.firstIndex(of: app) ?? 0

        Button("向前移动", systemImage: "arrow.left") {
            store.moveApp(app, inGroupID: groupID, by: -1)
        }
        .disabled(index == 0)
        Button("向后移动", systemImage: "arrow.right") {
            store.moveApp(app, inGroupID: groupID, by: 1)
        }
        .disabled(index >= orderedApps.count - 1)
        Divider()
        Menu("移到分组", systemImage: "folder") {
            ForEach(store.groups) { group in
                Button(group.name) { store.move(app, toGroupID: group.id) }
                    .disabled(store.group(for: app)?.id == group.id)
            }
        }
        Button("重命名", systemImage: "pencil") {
            aliasDraft = store.editableDisplayName(for: app)
            aliasTarget = app
        }
        Button("从空间和分组中隐藏", systemImage: "eye.slash") {
            store.setHidden(true, for: app)
        }
        Divider()
        Button("在访达中显示", systemImage: "folder") { store.revealInFinder(app) }
        Button("打开应用", systemImage: "arrow.up.forward.app") { store.launch(app) }
    }
}

struct DragPreview: View {
    let app: AppInfo

    var body: some View {
        AppIconContent(app: app, size: 58)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous))
    }
}

struct GroupDragPreview: View {
    let group: UserGroup
    let apps: [AppInfo]

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Palette.tint(for: group.tint))
                .frame(width: 11, height: 11)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(ZizaiTypography.groupTitle)
                    .foregroundStyle(Color.primary.opacity(ZizaiTypography.primaryLabelOpacity))
                Text("移动整个分组 · \(apps.count) 个应用")
                    .font(ZizaiTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: -5) {
                ForEach(Array(apps.prefix(5))) { app in
                    Image(nsImage: IconCache.shared.icon(for: app.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: ZizaiRadius.control, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 430, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ZizaiRadius.panel, style: .continuous)
                .stroke(Palette.tint(for: group.tint).opacity(0.30), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(ZizaiShadow.floatingOpacity),
            radius: ZizaiShadow.floatingRadius,
            y: ZizaiShadow.floatingY
        )
    }
}
