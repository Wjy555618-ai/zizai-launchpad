import CoreGraphics
import Foundation

enum LayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case groups = "分组"
    case space = "空间"
    case allApps = "全部应用"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .space: return "rectangle.3.group"
        case .groups: return "square.grid.2x2"
        case .allApps: return "square.grid.3x3"
        }
    }

    var usageDescription: String {
        switch self {
        case .groups:
            return "拖动应用换组或换序；拖动分组标题可以调整先后。"
        case .space:
            return "拖动应用或分组自由摆放；拖动分组任意边缘缩放，空白处平移空间。"
        case .allApps:
            return "这里管理这台 Mac 上的应用。隐藏只影响启动台显示，不会卸载。"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "空间", "自由画布": self = .space
        case "分组", "自动排列": self = .groups
        case "全部应用": self = .allApps
        default: self = .groups
        }
    }
}

enum AppGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case aiCreative = "AI 与创作"
    case communication = "沟通协作"
    case productivity = "办公效率"
    case entertainment = "影音娱乐"
    case utilities = "系统工具"
    case other = "其他应用"

    var id: String { stableID }

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    var stableID: String {
        switch self {
        case .aiCreative: return "ai-creative"
        case .communication: return "communication"
        case .productivity: return "productivity"
        case .entertainment: return "entertainment"
        case .utilities: return "utilities"
        case .other: return "other"
        }
    }

    var subtitle: String {
        switch self {
        case .aiCreative: return "设计、开发与智能工具"
        case .communication: return "消息、会议与团队协作"
        case .productivity: return "文档、计划与日常工作"
        case .entertainment: return "视频、音乐、阅读与游戏"
        case .utilities: return "设备、网络与系统管理"
        case .other: return "尚未归类的应用"
        }
    }
}

enum GroupTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, indigo, mint, pink, orange, teal, slate, purple
    var id: String { rawValue }

    var chineseName: String {
        switch self {
        case .blue: return "蓝色"
        case .indigo: return "靛蓝色"
        case .mint: return "薄荷色"
        case .pink: return "粉色"
        case .orange: return "橙色"
        case .teal: return "青色"
        case .slate: return "灰蓝色"
        case .purple: return "紫色"
        }
    }
}

struct AppInfo: Identifiable, Hashable, Sendable {
    let id: String
    let bundleIdentifier: String
    let name: String
    let chineseName: String
    let path: String
    let purpose: String
    let group: AppGroup

    var bundleFileName: String {
        URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
    }
}

extension String {
    /// Removes only non-rendering edge scalars. This is stricter than trimming
    /// whitespace because real application metadata can begin with bidi marks
    /// or contain nothing but zero-width format characters.
    var zizaiVisibleTrimmed: String {
        let scalars = Array(unicodeScalars)
        func isInvisibleEdge(_ scalar: Unicode.Scalar) -> Bool {
            scalar.properties.isWhitespace
                || scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .format
        }

        guard
            let first = scalars.firstIndex(where: { !isInvisibleEdge($0) }),
            let last = scalars.lastIndex(where: { !isInvisibleEdge($0) })
        else { return "" }

        return String(String.UnicodeScalarView(scalars[first...last]))
    }

    var zizaiVisibleNonEmpty: String? {
        let value = zizaiVisibleTrimmed
        return value.isEmpty ? nil : value
    }
}

struct StoredPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct StoredSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

struct UserGroup: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var subtitle: String
    var tint: GroupTint
    var center: StoredPoint
    var size: StoredSize
    var isStarterGroup: Bool
}

struct PersistedState: Codable, Equatable, Sendable {
    var schemaVersion = 8
    var positions: [String: StoredPoint] = [:]
    var aliases: [String: String] = [:]
    var hiddenAppIDs: Set<String> = []
    var appGroupIDs: [String: String] = [:]
    var groupAppOrder: [String: [String]] = [:]
    var userGroups: [UserGroup] = []
    var deletedStarterGroupIDs: Set<String> = []
    var layoutMode: LayoutMode = .groups
    var canvasOffsetX: Double = 0
    var canvasOffsetY: Double = 0
    var canvasScale: Double = 0.94
    var hasSeenWelcome = false

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, positions, aliases, hiddenAppIDs, appGroupIDs, groupAppOrder
        case userGroups, deletedStarterGroupIDs, layoutMode, canvasOffsetX, canvasOffsetY, canvasScale
        case hasSeenWelcome
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 3
        positions = try container.decodeIfPresent([String: StoredPoint].self, forKey: .positions) ?? [:]
        aliases = try container.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        hiddenAppIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenAppIDs) ?? []
        appGroupIDs = try container.decodeIfPresent([String: String].self, forKey: .appGroupIDs) ?? [:]
        groupAppOrder = try container.decodeIfPresent([String: [String]].self, forKey: .groupAppOrder) ?? [:]
        userGroups = try container.decodeIfPresent([UserGroup].self, forKey: .userGroups) ?? []
        deletedStarterGroupIDs =
            try container.decodeIfPresent(
                Set<String>.self,
                forKey: .deletedStarterGroupIDs
            ) ?? []
        layoutMode = (try? container.decode(LayoutMode.self, forKey: .layoutMode)) ?? .groups
        canvasOffsetX = try container.decodeIfPresent(Double.self, forKey: .canvasOffsetX) ?? 0
        canvasOffsetY = try container.decodeIfPresent(Double.self, forKey: .canvasOffsetY) ?? 0
        canvasScale = try container.decodeIfPresent(Double.self, forKey: .canvasScale) ?? 0.94
        hasSeenWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? false
    }
}

struct ToastNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let actionTitle: String?
}

struct AppMovePreview: Equatable {
    let appID: String
    let targetGroupID: String
    let requestedPoint: CGPoint
    let resolvedPoint: CGPoint?
    let displacedAppID: String?
    let displacedAppPosition: CGPoint?
}

struct GroupResizePreview: Equatable {
    let groupID: String
    let frame: CGRect
    let appPositions: [String: CGPoint]
}

struct GroupDraft: Identifiable {
    let id = UUID()
    var editingGroupID: String?
    var name: String
    var tint: GroupTint
    var center: CGPoint
}
