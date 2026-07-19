import UIKit
import Observation

protocol EnhancedStreamProvider {
    func remuxURL(videoURL: URL, audioURL: URL, item: MediaItem) async throws -> URL
}

nonisolated struct NativeSessionMetadata: Equatable {
    let subtitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let synopsis: String?
    let artworkURL: URL?
    let year: Int?
    let genres: [String]
    let runtimeMinutes: Int?
    let ageRatingLabel: String?
    let ratingLabel: String?
    let cast: [MediaItem.Person]
    let directors: [MediaItem.Person]

    init(
        subtitle: String?,
        synopsis: String?,
        artworkURL: URL?,
        year: Int?,
        genres: [String],
        runtimeMinutes: Int?,
        ageRatingLabel: String?,
        ratingLabel: String?,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        cast: [MediaItem.Person] = [],
        directors: [MediaItem.Person] = []
    ) {
        self.subtitle = subtitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.synopsis = synopsis
        self.artworkURL = artworkURL
        self.year = year
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.ageRatingLabel = ageRatingLabel
        self.ratingLabel = ratingLabel
        self.cast = cast
        self.directors = directors
    }
}

nonisolated struct NativePlaybackSession: Identifiable, Equatable {
    let id = UUID()
    let videoURL: URL
    let title: String
    let startSeconds: Int?
    var metadata: NativeSessionMetadata?
}

@Observable
final class PlaybackCoordinator {
    enum Route: Equatable {
        case infuse
        case externalService(StreamingService)
    }

    enum PlaybackError: Error, Equatable {
        case missingImdbId
        case notConfigured
        case noSources
        case noEpisodes
        case rateLimited
        case network
        case infuseNotInstalled
        case openFailed
        case infusePlaybackFailed
        case serviceOpenFailed(String)
        case enhancedUnavailable

        var message: String {
            switch self {
            case .missingImdbId:
                "Este título não tem identificador para buscar fontes."
            case .notConfigured:
                "Configure o servidor de streams (Secrets.plist) para reproduzir."
            case .noSources:
                "Nenhuma fonte encontrada para este título."
            case .noEpisodes:
                "Nenhum episódio disponível para esta série."
            case .rateLimited:
                "Muitas buscas em sequência. Tente novamente em instantes."
            case .network:
                "Servidor de streams inacessível. Verifique a conexão Tailscale."
            case .infuseNotInstalled:
                "O Infuse não está instalado nesta Apple TV."
            case .openFailed:
                "Não foi possível abrir o Infuse."
            case .infusePlaybackFailed:
                "O Infuse não conseguiu reproduzir esta fonte."
            case .serviceOpenFailed(let name):
                "Não foi possível abrir o app \(name)."
            case .enhancedUnavailable:
                "O modo Enhanced ainda não está disponível."
            }
        }
    }

    enum State: Equatable {
        case idle
        case loading
        case failed(PlaybackError)
    }

    private(set) var state: State = .idle
    private(set) var nativeSession: NativePlaybackSession?
    private var nativePosition: Int?
    let progressStore: PlaybackProgressStore

    private let api: StreamsAPI
    private let watchHub = WatchHubAPI()
    private var cache: [String: (fetchedAt: Date, streams: [AddonStream])] = [:]
    private var inFlight: [String: Task<[AddonStream], any Error>] = [:]
    private static let cacheTTL: TimeInterval = 60

    init(api: StreamsAPI = StreamsAPI(), progressStore: PlaybackProgressStore = PlaybackProgressStore()) {
        self.api = api
        self.progressStore = progressStore
    }

    func route(for item: MediaItem) -> Route {
        if item.kind == .movie, let service = item.streamingSource, service.isSubscribed {
            return .externalService(service)
        }
        return .infuse
    }

    func play(
        item: MediaItem,
        mode: PlaybackMode,
        engine: PlayerEngine = .infuse,
        preferredStream: AddonStream? = nil
    ) async {
        guard state != .loading, item.kind == .movie || item.isAnime else { return }
        switch route(for: item) {
        case .externalService(let service):
            await openExternal(service, item: item)
        case .infuse:
            await playViaInfuse(item: item, mode: mode, engine: engine, preferredStream: preferredStream)
        }
    }

    func play(
        item: MediaItem,
        episode: EpisodeItem,
        next: EpisodeItem?,
        mode: PlaybackMode,
        engine: PlayerEngine = .infuse,
        preferredStream: AddonStream? = nil
    ) async {
        guard state != .loading else { return }
        await playEpisodeViaInfuse(
            item: item,
            episode: episode,
            next: next,
            mode: mode,
            engine: engine,
            preferredStream: preferredStream
        )
    }

    func sources(for item: MediaItem, mode: PlaybackMode) async -> Result<[AddonStream], PlaybackError> {
        switch Self.streamQuery(for: item, mode: mode) {
        case .failure(let error):
            return .failure(error)
        case .success(let query):
            return await loadStreams(profile: query.profile, type: query.type, id: query.id)
                .map { $0.filter(\.isPlayable) }
        }
    }

    func sources(videoId: String, isAnime: Bool, mode: PlaybackMode) async -> Result<[AddonStream], PlaybackError> {
        switch Self.streamQuery(videoId: videoId, isAnime: isAnime, mode: mode) {
        case .failure(let error):
            return .failure(error)
        case .success(let query):
            return await loadStreams(profile: query.profile, type: query.type, id: videoId)
                .map { $0.filter(\.isPlayable) }
        }
    }

    func fail(_ error: PlaybackError) {
        state = .failed(error)
    }

    func handleIncomingURL(_ url: URL) {
        guard let callback = InfuseCallback(url: url) else { return }
        switch callback {
        case .success(let lastPlayedURL, let position):
            guard let lastPlayedURL, let position else { return }
            progressStore.applyCallback(lastPlayedURL: lastPlayedURL, position: position)
        case .error(_, _, let failedURLs):
            failedURLs.forEach { progressStore.discardSession(videoURL: $0) }
            state = .failed(.infusePlaybackFailed)
        }
    }

    func dismissError() {
        guard case .failed = state else { return }
        state = .idle
    }

    func startNativeSession(
        videoURL: URL,
        title: String,
        position: Int?,
        entry: ResumeEntry,
        episodeContext: EpisodeSessionContext? = nil,
        metadata: NativeSessionMetadata? = nil
    ) {
        progressStore.registerSession(
            videoURL: videoURL.absoluteString,
            entry: entry,
            episodeContext: episodeContext
        )
        nativePosition = nil
        nativeSession = NativePlaybackSession(videoURL: videoURL, title: title, startSeconds: position, metadata: metadata)
        state = .idle
    }

    func updateNativePosition(_ seconds: Int) {
        guard nativeSession != nil, seconds > 0 else { return }
        nativePosition = seconds
    }

    func completeNativeSession() {
        guard let session = nativeSession else { return }
        nativeSession = nil
        let videoURL = session.videoURL.absoluteString
        if let position = nativePosition {
            progressStore.applyCallback(lastPlayedURL: videoURL, position: position)
        } else {
            progressStore.discardSession(videoURL: videoURL)
        }
        nativePosition = nil
    }

    private func openExternal(_ service: StreamingService, item: MediaItem) async {
        state = .loading
        for url in await titleURLs(for: service, item: item) {
            if await UIApplication.shared.open(url) {
                state = .idle
                return
            }
        }
        for url in service.appURLs {
            if await UIApplication.shared.open(url) {
                state = .idle
                return
            }
        }
        state = .failed(.serviceOpenFailed(service.displayName))
    }

    private func titleURLs(for service: StreamingService, item: MediaItem) async -> [URL] {
        let id = item.imdbId ?? item.contentId
        guard let id, id.hasPrefix("tt"), !service.watchHubNames.isEmpty else { return [] }
        let streams = (try? await watchHub.streams(type: "movie", id: id)) ?? []
        let raw = streams
            .compactMap { stream -> String? in
                guard let name = stream.name, service.watchHubNames.contains(name) else { return nil }
                return stream.tvOsUrl
            }
            .first
        guard let raw else { return [] }
        var candidates: [URL] = []
        if !raw.hasPrefix("http"), let separator = raw.range(of: "://www.") {
            let webTwin = "https" + String(raw[separator.lowerBound...])
            if let url = URL(string: webTwin) {
                candidates.append(url)
            }
        }
        if let url = URL(string: raw), !candidates.contains(url) {
            candidates.append(url)
        }
        return candidates
    }

    private func playViaInfuse(item: MediaItem, mode: PlaybackMode, engine: PlayerEngine, preferredStream: AddonStream?) async {
        let query: (profile: StreamProfile, type: String, id: String)
        switch Self.streamQuery(for: item, mode: mode) {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let resolved):
            query = resolved
        }
        state = .loading
        let streams: [AddonStream]
        switch await loadStreams(profile: query.profile, type: query.type, id: query.id) {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let fetched):
            streams = fetched
        }
        guard let chosen = preferredStream ?? streams.first(where: \.isPlayable),
              let videoURL = chosen.playbackURL else {
            state = .failed(.noSources)
            return
        }
        let contentId = item.contentId ?? query.id
        let runtimeMinutes = RuntimeParser.minutes(from: item.runtime)
        let position = resumePosition(for: contentId, runtimeMinutes: runtimeMinutes)
        let entry = Self.resumeEntry(
            for: item,
            contentId: contentId,
            imdbId: Self.imdbId(for: item),
            runtimeMinutes: runtimeMinutes
        )
        if engine == .native {
            startNativeSession(
                videoURL: videoURL,
                title: item.title,
                position: position,
                entry: entry,
                metadata: Self.sessionMetadata(for: item, subtitle: nil, runtimeMinutes: runtimeMinutes)
            )
            return
        }
        guard InfuseLauncher.isInstalled else {
            state = .failed(.infuseNotInstalled)
            return
        }
        let playItem = InfusePlayItem(
            videoURL: videoURL,
            filename: Self.infuseFilename(for: item, filename: chosen.behaviorHints?.filename),
            positionSeconds: position
        )
        guard let url = InfuseURLBuilder.playURL(item: playItem) else {
            state = .failed(.openFailed)
            return
        }
        let videoURLString = videoURL.absoluteString
        progressStore.registerSession(videoURL: videoURLString, entry: entry)
        if await InfuseLauncher.open(url) {
            state = .idle
        } else {
            progressStore.discardSession(videoURL: videoURLString)
            state = .failed(.openFailed)
        }
    }

    private func playEpisodeViaInfuse(
        item: MediaItem,
        episode: EpisodeItem,
        next: EpisodeItem?,
        mode: PlaybackMode,
        engine: PlayerEngine,
        preferredStream: AddonStream?
    ) async {
        let query: (profile: StreamProfile, type: String)
        switch Self.streamQuery(videoId: episode.videoId, isAnime: item.isAnime, mode: mode) {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let resolved):
            query = resolved
        }
        state = .loading
        let streams: [AddonStream]
        switch await loadStreams(profile: query.profile, type: query.type, id: episode.videoId) {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let fetched):
            streams = fetched
        }
        guard let chosen = preferredStream ?? streams.first(where: \.isPlayable),
              let videoURL = chosen.playbackURL else {
            state = .failed(.noSources)
            return
        }
        let seriesId = PlaybackProgressStore.seriesKey(for: item) ?? episode.videoId
        let position = resumePosition(
            seriesId: seriesId,
            videoId: episode.videoId,
            runtimeMinutes: episode.runtimeMinutes
        )
        let context = EpisodeSessionContext(
            seriesId: seriesId,
            videoId: episode.videoId,
            season: episode.season,
            episode: episode.episode,
            next: next.map {
                NextEpisodeRef(
                    videoId: $0.videoId,
                    season: $0.season,
                    episode: $0.episode,
                    title: $0.title,
                    runtimeMinutes: $0.runtimeMinutes
                )
            }
        )
        let entry = Self.resumeEntry(for: item, seriesId: seriesId, episode: episode)
        if engine == .native {
            startNativeSession(
                videoURL: videoURL,
                title: item.title,
                position: position,
                entry: entry,
                episodeContext: context,
                metadata: Self.sessionMetadata(
                    for: item,
                    subtitle: episode.title.isEmpty ? nil : episode.title,
                    runtimeMinutes: episode.runtimeMinutes,
                    seasonNumber: episode.season,
                    episodeNumber: episode.episode
                )
            )
            return
        }
        guard InfuseLauncher.isInstalled else {
            state = .failed(.infuseNotInstalled)
            return
        }
        let playItem = InfusePlayItem(
            videoURL: videoURL,
            filename: Self.infuseFilename(item: item, episode: episode, filename: chosen.behaviorHints?.filename),
            positionSeconds: position
        )
        guard let url = InfuseURLBuilder.playURL(item: playItem) else {
            state = .failed(.openFailed)
            return
        }
        let videoURLString = videoURL.absoluteString
        progressStore.registerSession(videoURL: videoURLString, entry: entry, episodeContext: context)
        if await InfuseLauncher.open(url) {
            state = .idle
        } else {
            progressStore.discardSession(videoURL: videoURLString)
            state = .failed(.openFailed)
        }
    }

    private func loadStreams(profile: StreamProfile, type: String, id: String) async -> Result<[AddonStream], PlaybackError> {
        do {
            return .success(try await fetchStreams(profile: profile, type: type, id: id))
        } catch let error as StreamsAPIError {
            return .failure(Self.playbackError(for: error))
        } catch {
            return .failure(.network)
        }
    }

    private func fetchStreams(profile: StreamProfile, type: String, id: String) async throws -> [AddonStream] {
        let key = "\(profile.rawValue)|\(type)|\(id)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            return cached.streams
        }
        if let running = inFlight[key] {
            return try await running.value
        }
        let api = self.api
        let task = Task { try await api.streams(profile: profile, type: type, id: id) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let streams = try await task.value
        cache[key] = (Date(), streams)
        return streams
    }

    private func resumePosition(for contentId: String, runtimeMinutes: Int?) -> Int? {
        guard let position = progressStore.position(for: contentId), position >= 30 else { return nil }
        if let runtimeMinutes, runtimeMinutes > 0,
           Double(position) > Double(runtimeMinutes * 60) * 0.95 {
            return nil
        }
        return position
    }

    private func resumePosition(seriesId: String, videoId: String, runtimeMinutes: Int?) -> Int? {
        guard let entry = progressStore.entries.first(where: { $0.contentId == seriesId }),
              entry.videoId == videoId,
              entry.positionSeconds >= 30 else { return nil }
        if let runtimeMinutes, runtimeMinutes > 0,
           Double(entry.positionSeconds) > Double(runtimeMinutes * 60) * 0.95 {
            return nil
        }
        return entry.positionSeconds
    }

    private static func streamQuery(
        for item: MediaItem,
        mode: PlaybackMode
    ) -> Result<(profile: StreamProfile, type: String, id: String), PlaybackError> {
        if item.isAnime {
            guard let animeId = animeStreamId(for: item) else { return .failure(.missingImdbId) }
            return .success((.anime, "anime", animeId))
        }
        guard let profile = StreamProfile(mode: mode) else { return .failure(.enhancedUnavailable) }
        guard let imdbId = imdbId(for: item) else { return .failure(.missingImdbId) }
        return .success((profile, "movie", imdbId))
    }

    private static func streamQuery(
        videoId: String,
        isAnime: Bool,
        mode: PlaybackMode
    ) -> Result<(profile: StreamProfile, type: String), PlaybackError> {
        let request = streamRequest(videoId: videoId, isAnime: isAnime)
        if let fixed = request.profile {
            return .success((fixed, request.type))
        }
        guard let profile = StreamProfile(mode: mode) else { return .failure(.enhancedUnavailable) }
        return .success((profile, request.type))
    }

    nonisolated static func streamRequest(videoId: String, isAnime: Bool) -> (type: String, profile: StreamProfile?) {
        let animePrefixes = ["kitsu:", "mal:", "anilist:"]
        if animePrefixes.contains(where: videoId.hasPrefix) {
            return ("anime", .anime)
        }
        if isAnime {
            return ("series", .anime)
        }
        return ("series", nil)
    }

    private static func imdbId(for item: MediaItem) -> String? {
        if let id = item.imdbId, id.hasPrefix("tt") { return id }
        if let id = item.contentId, id.hasPrefix("tt") { return id }
        return nil
    }

    private static func animeStreamId(for item: MediaItem) -> String? {
        if let id = item.contentId, id.hasPrefix("mal:") || id.hasPrefix("kitsu:") { return id }
        return imdbId(for: item)
    }

    private static func playbackError(for error: StreamsAPIError) -> PlaybackError {
        switch error {
        case .notConfigured: .notConfigured
        case .rateLimited: .rateLimited
        case .invalidURL: .notConfigured
        case .badStatus, .transport: .network
        case .decoding: .noSources
        }
    }

    private static func infuseFilename(for item: MediaItem, filename: String?) -> String {
        let ext = fileExtension(from: filename)
        guard item.year > 0 else { return "\(item.title).\(ext)" }
        return "\(item.title) (\(item.year)).\(ext)"
    }

    nonisolated static func infuseFilename(item: MediaItem, episode: EpisodeItem, filename: String?) -> String {
        let code = String(format: "S%02dE%02d", episode.season, episode.episode)
        return "\(item.title) \(code).\(fileExtension(from: filename))"
    }

    nonisolated private static func fileExtension(from filename: String?) -> String {
        let knownExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "ts", "webm", "mov"]
        return filename
            .map { ($0 as NSString).pathExtension.lowercased() }
            .flatMap { knownExtensions.contains($0) ? $0 : nil }
            ?? "mkv"
    }

    private static func sessionMetadata(
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

    private static func resumeEntry(for item: MediaItem, seriesId: String, episode: EpisodeItem) -> ResumeEntry {
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

    private static func resumeEntry(
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
