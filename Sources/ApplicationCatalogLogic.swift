import Foundation

/// Pure catalog policy shared by the store and tests. Search vocabulary and
/// legacy identity migration belong to the application catalog, not to the
/// observable UI state coordinator.
enum ApplicationCatalogLogic {
    static func searchDocument(
        for app: AppInfo,
        displayName: String,
        groupName: String
    ) -> ApplicationSearchDocument {
        let key = "\(app.name) \(app.bundleIdentifier)".lowercased()
        var aliases: [String] = []
        if key.contains("wechat") || app.chineseName.contains("微信") {
            aliases.append(contentsOf: ["微信", "微信聊天", "WeChat"])
        }
        if key.contains("messages") || key.contains("mobilesms") {
            aliases.append(contentsOf: ["信息", "短信", "iMessage"])
        }
        if key.contains("codex") {
            aliases.append(contentsOf: ["Codex", "OpenAI Codex", "代码助手"])
        }
        return ApplicationSearchDocument(
            userFacingTerms: [
                displayName,
                app.chineseName,
                app.name,
                app.purpose,
                groupName,
            ] + aliases,
            technicalTerms: [
                app.bundleFileName,
                app.bundleIdentifier,
                app.path,
            ]
        )
    }

    static func migrateLegacyIdentity(state: inout PersistedState, apps: [AppInfo]) {
        let currentIDs = Set(apps.map(\.id))
        let families = Dictionary(grouping: apps, by: \.bundleIdentifier)
        var replacements: [String: String] = [:]

        for (legacyID, family) in families where !currentIDs.contains(legacyID) {
            guard
                let primary = family.min(by: { lhs, rhs in
                    let leftDepth = URL(fileURLWithPath: lhs.path).pathComponents.count
                    let rightDepth = URL(fileURLWithPath: rhs.path).pathComponents.count
                    if leftDepth != rightDepth { return leftDepth < rightDepth }
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                })
            else { continue }
            replacements[legacyID] = primary.id
        }

        for (legacyID, newID) in replacements {
            moveValue(in: &state.positions, from: legacyID, to: newID)
            moveValue(in: &state.aliases, from: legacyID, to: newID)
            moveValue(in: &state.appGroupIDs, from: legacyID, to: newID)
            if state.hiddenAppIDs.remove(legacyID) != nil {
                state.hiddenAppIDs.insert(newID)
            }
        }

        state.groupAppOrder = state.groupAppOrder.mapValues { order in
            var seen = Set<String>()
            return order.compactMap { legacyID in
                let resolved = replacements[legacyID] ?? legacyID
                return seen.insert(resolved).inserted ? resolved : nil
            }
        }
    }

    private static func moveValue<Value>(
        in dictionary: inout [String: Value],
        from legacyID: String,
        to newID: String
    ) {
        if dictionary[newID] == nil,
            let value = dictionary.removeValue(forKey: legacyID)
        {
            dictionary[newID] = value
        } else {
            dictionary.removeValue(forKey: legacyID)
        }
    }
}
