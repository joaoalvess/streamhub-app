import Foundation

nonisolated enum PlayPlanner {
    nonisolated enum Context {
        case movie
        case loaded(next: EpisodeItem?, nextAfter: EpisodeItem?, defaultVideoId: String?)
        case unavailable(defaultVideoId: String?)
        case pending(resume: ResumeEntry?)
    }

    static func isSeriesLike(_ item: MediaItem) -> Bool {
        item.kind == .series || item.isAnime
    }

    static func seriesId(for item: MediaItem) -> String {
        PlaybackProgressStore.seriesKey(for: item) ?? item.contentId ?? ""
    }

    static func resumeEpisode(from entry: ResumeEntry?, item: MediaItem) -> EpisodeItem? {
        guard let entry, let videoId = entry.videoId else { return nil }
        return EpisodeItem(
            videoId: videoId,
            season: entry.season ?? 1,
            episode: entry.episode ?? 1,
            title: entry.episodeTitle ?? item.title,
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: entry.runtimeMinutes,
            isReleased: true
        )
    }

    static func resumeLabel(for entry: ResumeEntry?) -> String {
        if let entry, entry.videoId != nil, let code = entry.episodeCode {
            return entry.positionSeconds > 0 ? "Continuar \(code)" : "Reproduzir \(code)"
        }
        return "Reproduzir"
    }

    static func isPlayEnabled(for item: MediaItem, in context: Context) -> Bool {
        switch context {
        case .movie:
            return true
        case .loaded(let next, _, let defaultVideoId):
            if next != nil {
                return true
            }
            return item.kind == .series && !item.isAnime
                && defaultVideoId != nil
        case .unavailable:
            return true
        case .pending(let resume):
            return resumeEpisode(from: resume, item: item) != nil
        }
    }

    static func resolveTarget(for item: MediaItem, in context: Context) -> PlayResolution {
        switch context {
        case .movie:
            return .target(.movie)
        case .loaded(let next, let nextAfter, let defaultVideoId):
            if let next {
                return .target(.episode(next, next: nextAfter))
            }
            if item.kind == .series, !item.isAnime {
                return fallbackTarget(for: item, defaultVideoId: defaultVideoId)
            }
            return .blocked(.noEpisodes)
        case .unavailable(let defaultVideoId):
            if item.kind == .series, !item.isAnime {
                return fallbackTarget(for: item, defaultVideoId: defaultVideoId)
            }
            return .target(.movie)
        case .pending(let resume):
            guard let episode = resumeEpisode(from: resume, item: item) else { return .pending }
            return .target(.episode(episode, next: nil))
        }
    }

    static func contentKey(for target: PlayTarget, item: MediaItem) -> String? {
        switch target {
        case .movie:
            return item.contentId
        case .episode(let episode, _):
            return episode.videoId
        }
    }

    private static func fallbackTarget(for item: MediaItem, defaultVideoId: String?) -> PlayResolution {
        guard let defaultId = defaultVideoId else {
            return .blocked(.noEpisodes)
        }
        let episode = EpisodeItem(
            videoId: defaultId,
            season: 1,
            episode: 1,
            title: item.title,
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: RuntimeParser.minutes(from: item.runtime),
            isReleased: true
        )
        return .target(.episode(episode, next: nil))
    }
}
