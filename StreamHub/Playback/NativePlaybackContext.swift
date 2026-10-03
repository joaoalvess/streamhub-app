import Foundation

nonisolated struct NativePlaybackContext {
    let item: MediaItem
    let episode: EpisodeItem?
    let next: EpisodeItem?
    let timeline: EpisodeTimeline?
    let mode: PlaybackMode
    var bingeGroup: String?
}

nonisolated struct NativeSourceOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let isSelected: Bool
}

nonisolated enum UpNextPlanner {
    static let prefetchLead = 120

    static func shouldPrefetch(position: Int, duration: Int?, lead: Int = prefetchLead) -> Bool {
        guard let duration, duration > 0, position > 0 else { return false }
        return duration - position <= lead
    }

    static func stream(in streams: [AddonStream], bingeGroup: String?) -> AddonStream? {
        let playable = streams.filter(\.isPlayable)
        if let bingeGroup,
           let match = playable.first(where: { $0.behaviorHints?.bingeGroup == bingeGroup }) {
            return match
        }
        return playable.first
    }

    static func sourceOptions(from streams: [AddonStream], current: URL?) -> [NativeSourceOption] {
        var seen = Set<String>()
        return streams.compactMap { stream in
            guard let url = stream.playbackURL, seen.insert(url.absoluteString).inserted else { return nil }
            return NativeSourceOption(
                id: url.absoluteString,
                title: stream.name ?? "Fonte",
                subtitle: stream.description,
                isSelected: url == current
            )
        }
    }

    static func upNextSubtitle(for episode: EpisodeItem) -> String {
        guard !episode.title.isEmpty else { return episode.code }
        return "\(episode.code) · \(episode.title)"
    }
}
