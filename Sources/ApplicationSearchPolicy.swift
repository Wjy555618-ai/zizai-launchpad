import Foundation

/// Search input is separated by meaning. User-facing vocabulary may use
/// ordered-letter fuzzy matching; technical identity fields may only match
/// contiguously so bundle paths cannot pollute a strong name match.
struct ApplicationSearchDocument: Equatable {
    let userFacingTerms: [String]
    let technicalTerms: [String]
}

enum SearchMatchTier: Int, Comparable {
    case exact
    case prefix
    case substring
    case fuzzy

    static func < (lhs: SearchMatchTier, rhs: SearchMatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ApplicationSearchMatch: Comparable, Equatable {
    let tier: SearchMatchTier
    let detailScore: Int

    static func < (lhs: ApplicationSearchMatch, rhs: ApplicationSearchMatch) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        return lhs.detailScore < rhs.detailScore
    }
}

enum ApplicationSearchPolicy {
    static func match(
        query: String,
        document: ApplicationSearchDocument
    ) -> ApplicationSearchMatch? {
        let needle = normalize(query)
        guard !needle.isEmpty else {
            return ApplicationSearchMatch(tier: .exact, detailScore: 0)
        }

        let visibleMatches = document.userFacingTerms.compactMap {
            score(needle: needle, candidate: $0, allowsFuzzy: true)
        }
        let technicalMatches = document.technicalTerms.compactMap {
            score(needle: needle, candidate: $0, allowsFuzzy: false)
        }
        return (visibleMatches + technicalMatches).min()
    }

    /// Fuzzy results are a fallback, never noise beside a stronger exact,
    /// prefix, or contiguous substring result. This keeps short queries such
    /// as `fig` precise while retaining intentional fuzzy input such as `fga`.
    static func preferredMatches<Value>(
        _ matches: [(value: Value, match: ApplicationSearchMatch)]
    ) -> [(value: Value, match: ApplicationSearchMatch)] {
        guard let bestTier = matches.map(\.match.tier).min() else { return [] }
        let maximumTier: SearchMatchTier = bestTier == .fuzzy ? .fuzzy : .substring
        return matches.filter { $0.match.tier <= maximumTier }
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func score(
        needle: String,
        candidate: String,
        allowsFuzzy: Bool
    ) -> ApplicationSearchMatch? {
        let haystack = normalize(candidate)
        guard !haystack.isEmpty else { return nil }
        let lengthDelta = max(0, haystack.count - needle.count)

        if haystack == needle {
            return ApplicationSearchMatch(tier: .exact, detailScore: 0)
        }
        if haystack.hasPrefix(needle) {
            return ApplicationSearchMatch(tier: .prefix, detailScore: lengthDelta)
        }
        if let range = haystack.range(of: needle) {
            let offset = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            return ApplicationSearchMatch(
                tier: .substring,
                detailScore: offset * 100 + lengthDelta
            )
        }
        guard allowsFuzzy, needle.count >= 2,
            let span = orderedSubsequenceSpan(needle, in: haystack)
        else { return nil }
        return ApplicationSearchMatch(
            tier: .fuzzy,
            detailScore: span * 100 + lengthDelta
        )
    }

    private static func orderedSubsequenceSpan(_ needle: String, in haystack: String) -> Int? {
        let expected = Array(needle)
        guard !expected.isEmpty else { return 0 }

        var needleIndex = 0
        var firstMatch: Int?
        var lastMatch = 0
        for (offset, character) in haystack.enumerated() where character == expected[needleIndex] {
            firstMatch = firstMatch ?? offset
            lastMatch = offset
            needleIndex += 1
            if needleIndex == expected.count {
                return lastMatch - (firstMatch ?? lastMatch) + 1
            }
        }
        return nil
    }
}
