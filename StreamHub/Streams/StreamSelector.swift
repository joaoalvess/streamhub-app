import Foundation

enum StreamSelector {
    static func playable(from streams: [AddonStream]) -> [StreamCandidate] {
        streams.compactMap(StreamCandidate.init(stream:))
    }

    static func validated(_ candidates: [StreamCandidate], title: String, year: Int) -> [StreamCandidate] {
        candidates.filter { matchesTitleYear($0.matchText, title: title, year: year) }
    }

    static func best(_ candidates: [StreamCandidate], mode: PlaybackMode) -> StreamCandidate? {
        switch mode {
        case .dubbed:
            let dubbed = candidates.filter(\.hasPTAudio)
            let pool = dubbed.isEmpty ? candidates : dubbed
            return pool.max { lexLess(qualityKey($0), qualityKey($1)) }
        case .subtitled:
            return candidates.max { lexLess(subtitledKey($0), subtitledKey($1)) }
        case .enhanced:
            return nil
        }
    }

    static func matchesTitleYear(_ text: String, title: String, year: Int) -> Bool {
        let textTokens = tokens(from: text)
        guard !textTokens.isEmpty else { return false }
        if year > 0 {
            let years = Set([year - 1, year, year + 1].map(String.init))
            if !years.isDisjoint(with: textTokens) { return true }
        }
        let titleTokens = tokens(from: title).filter { $0.count >= 3 && !stopwords.contains($0) }
        guard !titleTokens.isEmpty else { return false }
        let matched = titleTokens.filter(textTokens.contains)
        return matched.count * 2 >= titleTokens.count
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "los", "las", "les", "der", "die", "das",
        "uma", "una", "dos", "com", "que", "del", "por", "para"
    ]

    private static func qualityKey(_ candidate: StreamCandidate) -> [Int64] {
        [
            candidate.isCached ? 1 : 0,
            Int64(candidate.resolution),
            Int64(candidate.hdrScore),
            candidate.sizeBytes,
            Int64(candidate.seeds)
        ]
    }

    private static func subtitledKey(_ candidate: StreamCandidate) -> [Int64] {
        [candidate.hasOriginalAudio ? 1 : 0] + qualityKey(candidate)
    }

    private static func lexLess(_ lhs: [Int64], _ rhs: [Int64]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left < right
        }
        return false
    }

    private static func tokens(from text: String) -> Set<String> {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        return Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }
}
