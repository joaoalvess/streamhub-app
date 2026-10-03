import Foundation

nonisolated struct EpisodeItem: Identifiable, Hashable, Sendable {
    let videoId: String
    let season: Int
    let episode: Int
    let title: String
    let overview: String?
    let thumbnailURL: URL?
    let releasedAt: Date?
    let runtimeMinutes: Int?
    let isReleased: Bool

    var id: String { videoId }
    var code: String { "T\(season)E\(episode)" }
}

nonisolated struct SeasonGroup: Identifiable, Hashable, Sendable {
    let number: Int
    let episodes: [EpisodeItem]

    var id: Int { number }
    var label: String { number == 0 ? "Especiais" : "Temporada \(number)" }
}

nonisolated struct EpisodeTimeline: Sendable {
    private static let completionThreshold = 0.92

    let seasons: [SeasonGroup]
    private let order: [EpisodeItem]
    private let orderPositions: [String: Int]
    private let seasonPositions: [Int: [String: Int]]

    init(seasons: [SeasonGroup]) {
        self.seasons = seasons
        let order = seasons
            .filter { $0.number != 0 }
            .flatMap { $0.episodes.filter(\.isReleased) }
        self.order = order
        orderPositions = Self.firstPositions(of: order)
        var seasonPositions: [Int: [String: Int]] = [:]
        for group in seasons {
            seasonPositions[group.number] = Self.firstPositions(of: group.episodes)
        }
        self.seasonPositions = seasonPositions
    }

    func nextUnwatched(resume: ResumeEntry?, watched: Set<String>) -> EpisodeItem? {
        guard !order.isEmpty else { return nil }
        if let resume, let videoId = resume.videoId {
            if let position = orderPositions[videoId],
               (resume.progress ?? 0) < Self.completionThreshold {
                return order[position]
            }
            let known = seasonPositions.values.contains { $0[videoId] != nil }
            if !known,
               let season = resume.season,
               let episode = resume.episode,
               let match = order.first(where: { $0.season == season && $0.episode == episode }) {
                return match
            }
        }
        return order.first { !watched.contains($0.videoId) } ?? order.first
    }

    func episodeAfter(_ episode: EpisodeItem) -> EpisodeItem? {
        guard let index = orderPositions[episode.videoId] else { return nil }
        let nextIndex = index + 1
        guard nextIndex < order.count else { return nil }
        return order[nextIndex]
    }

    func position(of episode: EpisodeItem) -> Int? {
        seasonPositions[episode.season]?[episode.videoId]
    }

    private static func firstPositions(of episodes: [EpisodeItem]) -> [String: Int] {
        var positions: [String: Int] = [:]
        for (index, episode) in episodes.enumerated() where positions[episode.videoId] == nil {
            positions[episode.videoId] = index
        }
        return positions
    }
}

nonisolated struct SeriesProgress {
    let resume: ResumeEntry?
    let watched: Set<String>
    let next: EpisodeItem?

    func progress(for episode: EpisodeItem) -> Double? {
        guard let resume, resume.videoId == episode.videoId else { return nil }
        return resume.progress
    }

    func isWatched(_ episode: EpisodeItem) -> Bool {
        watched.contains(episode.videoId)
    }
}

nonisolated enum EpisodePlanner {
    private static let fractionalDateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let dateStyle = Date.ISO8601FormatStyle()

    @concurrent
    static func timeline(from videos: [MetaVideo], fallbackRuntimeMinutes: Int?) async -> EpisodeTimeline {
        EpisodeTimeline(seasons: seasons(from: videos, fallbackRuntimeMinutes: fallbackRuntimeMinutes))
    }

    static func seasons(
        from videos: [MetaVideo],
        fallbackRuntimeMinutes: Int?,
        now: Date = .now
    ) -> [SeasonGroup] {
        let grouped = Dictionary(grouping: videos) { $0.season ?? 1 }
        let numbers = grouped.keys.sorted { lhs, rhs in
            if lhs == 0 { return false }
            if rhs == 0 { return true }
            return lhs < rhs
        }
        return numbers.compactMap { number in
            guard let group = grouped[number] else { return nil }
            let episodes = group
                .map { item(from: $0, fallbackRuntimeMinutes: fallbackRuntimeMinutes, now: now) }
                .sorted { $0.episode < $1.episode }
            return SeasonGroup(number: number, episodes: episodes)
        }
    }

    static func nextUnwatched(
        seasons: [SeasonGroup],
        resume: ResumeEntry?,
        watched: Set<String>
    ) -> EpisodeItem? {
        EpisodeTimeline(seasons: seasons).nextUnwatched(resume: resume, watched: watched)
    }

    static func episodeAfter(_ episode: EpisodeItem, seasons: [SeasonGroup]) -> EpisodeItem? {
        EpisodeTimeline(seasons: seasons).episodeAfter(episode)
    }

    static func defaultSeasonIndex(seasons: [SeasonGroup], next: EpisodeItem?) -> Int {
        if let next,
           let index = seasons.firstIndex(where: { group in
               group.episodes.contains { $0.videoId == next.videoId }
           }) {
            return index
        }
        return seasons.firstIndex { $0.number != 0 } ?? 0
    }

    static func playLabel(next: EpisodeItem?, resume: ResumeEntry?) -> String {
        guard let next else { return "Reproduzir" }
        if let resume, resume.videoId == next.videoId, resume.positionSeconds > 0 {
            return "Continuar \(next.code)"
        }
        return "Reproduzir \(next.code)"
    }

    private static func item(
        from video: MetaVideo,
        fallbackRuntimeMinutes: Int?,
        now: Date
    ) -> EpisodeItem {
        let episode = video.episode ?? 0
        let releasedAt = releaseDate(from: video.released)
        let title: String
        if let raw = video.title, !raw.isEmpty {
            title = raw
        } else {
            title = "Episódio \(episode)"
        }
        return EpisodeItem(
            videoId: video.id,
            season: video.season ?? 1,
            episode: episode,
            title: title,
            overview: video.overview,
            thumbnailURL: video.thumbnail.flatMap(URL.init(string:)),
            releasedAt: releasedAt,
            runtimeMinutes: RuntimeParser.minutes(from: video.runtime?.value) ?? fallbackRuntimeMinutes,
            isReleased: video.available ?? (releasedAt.map { $0 <= now } ?? true)
        )
    }

    private static func releaseDate(from string: String?) -> Date? {
        guard let string else { return nil }
        if let date = try? fractionalDateStyle.parse(string) {
            return date
        }
        return try? dateStyle.parse(string)
    }
}
