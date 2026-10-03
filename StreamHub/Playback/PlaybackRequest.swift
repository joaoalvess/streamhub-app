import Foundation

nonisolated enum PlaybackRequest {
    static func streamQuery(
        for item: MediaItem,
        mode: PlaybackMode
    ) -> Result<(profile: StreamProfile, type: String, id: String), PlaybackCoordinator.PlaybackError> {
        if item.isAnime {
            guard let animeId = animeStreamId(for: item) else { return .failure(.missingImdbId) }
            return .success((.anime, "anime", animeId))
        }
        guard let profile = StreamProfile(mode: mode) else { return .failure(.enhancedUnavailable) }
        guard let imdbId = imdbId(for: item) else { return .failure(.missingImdbId) }
        return .success((profile, "movie", imdbId))
    }

    static func streamQuery(
        videoId: String,
        isAnime: Bool,
        mode: PlaybackMode
    ) -> Result<(profile: StreamProfile, type: String), PlaybackCoordinator.PlaybackError> {
        let request = streamRequest(videoId: videoId, isAnime: isAnime)
        if let fixed = request.profile {
            return .success((fixed, request.type))
        }
        guard let profile = StreamProfile(mode: mode) else { return .failure(.enhancedUnavailable) }
        return .success((profile, request.type))
    }

    static func streamRequest(videoId: String, isAnime: Bool) -> (type: String, profile: StreamProfile?) {
        let animePrefixes = ["kitsu:", "mal:", "anilist:"]
        if animePrefixes.contains(where: videoId.hasPrefix) {
            return ("anime", .anime)
        }
        if isAnime {
            return ("series", .anime)
        }
        return ("series", nil)
    }

    static func imdbId(for item: MediaItem) -> String? {
        if let id = item.imdbId, id.hasPrefix("tt") { return id }
        if let id = item.contentId, id.hasPrefix("tt") { return id }
        return nil
    }

    private static func animeStreamId(for item: MediaItem) -> String? {
        if let id = item.contentId, id.hasPrefix("mal:") || id.hasPrefix("kitsu:") { return id }
        return imdbId(for: item)
    }

    static func playbackError(for error: StreamsAPIError) -> PlaybackCoordinator.PlaybackError {
        switch error {
        case .notConfigured: .notConfigured
        case .rateLimited: .rateLimited
        case .invalidURL: .notConfigured
        case .badStatus, .transport: .network
        case .decoding: .noSources
        }
    }

    static func infuseFilename(for item: MediaItem, filename: String?) -> String {
        let ext = fileExtension(from: filename)
        guard item.year > 0 else { return "\(item.title).\(ext)" }
        return "\(item.title) (\(item.year)).\(ext)"
    }

    static func infuseFilename(item: MediaItem, episode: EpisodeItem, filename: String?) -> String {
        let code = String(format: "S%02dE%02d", episode.season, episode.episode)
        return "\(item.title) \(code).\(fileExtension(from: filename))"
    }

    private static func fileExtension(from filename: String?) -> String {
        let knownExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "ts", "webm", "mov"]
        return filename
            .map { ($0 as NSString).pathExtension.lowercased() }
            .flatMap { knownExtensions.contains($0) ? $0 : nil }
            ?? "mkv"
    }

    static func sessionMetadata(
        for item: MediaItem,
        subtitle: String?,
        runtimeMinutes: Int?,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) -> NativeSessionMetadata {
        NativeSessionMetadata(
            subtitle: subtitle,
            synopsis: item.synopsis.isEmpty ? nil : item.synopsis,
            artworkURL: item.backdropURL ?? item.posterURL,
            year: item.year > 0 ? item.year : nil,
            genres: item.genres,
            runtimeMinutes: runtimeMinutes,
            ageRatingLabel: item.ageRating?.label,
            ratingLabel: item.imdbRating,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            cast: item.cast,
            directors: item.directors
        )
    }

    static func resumeEntry(for item: MediaItem, seriesId: String, episode: EpisodeItem) -> ResumeEntry {
        ResumeEntry(
            contentId: seriesId,
            imdbId: imdbId(for: item),
            title: item.title,
            year: item.year,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            logoURL: item.logoURL,
            runtimeMinutes: episode.runtimeMinutes,
            positionSeconds: 0,
            updatedAt: Date(),
            serviceCode: item.streamingSource?.rawValue,
            synopsis: item.synopsis,
            genres: item.genres,
            mediaKind: item.kind.rawValue,
            metaId: item.contentId,
            videoId: episode.videoId,
            season: episode.season,
            episode: episode.episode,
            episodeTitle: episode.title
        )
    }

    static func resumeEntry(
        for item: MediaItem,
        contentId: String,
        imdbId: String?,
        runtimeMinutes: Int?
    ) -> ResumeEntry {
        ResumeEntry(
            contentId: contentId,
            imdbId: imdbId,
            title: item.title,
            year: item.year,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            logoURL: item.logoURL,
            runtimeMinutes: runtimeMinutes,
            positionSeconds: 0,
            updatedAt: Date(),
            serviceCode: item.streamingSource?.rawValue,
            synopsis: item.synopsis,
            genres: item.genres,
            mediaKind: item.kind.rawValue
        )
    }
}
