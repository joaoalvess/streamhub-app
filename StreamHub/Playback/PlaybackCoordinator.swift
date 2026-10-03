import UIKit
import Observation

protocol EnhancedStreamProvider {
    func remuxURL(videoURL: URL, audioURL: URL, item: MediaItem) async throws -> URL
}

@Observable
final class PlaybackCoordinator {
    enum Route: Equatable {
        case infuse
        case externalService(StreamingService)
    }

    nonisolated enum PlaybackError: Error, Equatable {
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
                "Não foi possível conectar ao servidor de streams. Verifique sua conexão e tente novamente."
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
    private var nativeDuration: Int?
    private static let checkpointInterval = 15
    private var lastCheckpoint: Int?
    var nativePositionSeconds: Int? { nativePosition }
    private(set) var lastEndedNativePosition: Int?
    let progressStore: PlaybackProgressStore

    private let api: StreamsAPI
    private let watchHub = WatchHubAPI()
    private let cache = AsyncTTLCache<String, [AddonStream]>(ttl: 60, capacity: 10, shouldStore: { !$0.isEmpty })
    private var playGeneration = 0
    private let trackPreferenceStore: TrackPreferenceStore
    @ObservationIgnored private var nativeContext: NativePlaybackContext?
    @ObservationIgnored private var nativePreferenceScope = TrackPreferenceScope.global
    @ObservationIgnored private var nativeSourceStreams: [AddonStream] = []
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchedNext: (videoId: String, stream: AddonStream)?
    @ObservationIgnored private var isAdvancing = false

    init(
        api: StreamsAPI = StreamsAPI(),
        progressStore: PlaybackProgressStore = PlaybackProgressStore(),
        trackPreferenceStore: TrackPreferenceStore = TrackPreferenceStore()
    ) {
        self.api = api
        self.progressStore = progressStore
        self.trackPreferenceStore = trackPreferenceStore
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
        let generation = beginPlay()
        switch route(for: item) {
        case .externalService(let service):
            await openExternal(service, item: item, generation: generation)
        case .infuse:
            await playViaInfuse(
                item: item,
                mode: mode,
                engine: engine,
                preferredStream: preferredStream,
                generation: generation
            )
        }
    }

    func play(
        item: MediaItem,
        episode: EpisodeItem,
        next: EpisodeItem?,
        timeline: EpisodeTimeline? = nil,
        mode: PlaybackMode,
        engine: PlayerEngine = .infuse,
        preferredStream: AddonStream? = nil
    ) async {
        guard state != .loading else { return }
        await playEpisodeViaInfuse(
            item: item,
            episode: episode,
            next: next,
            timeline: timeline,
            mode: mode,
            engine: engine,
            preferredStream: preferredStream,
            generation: beginPlay()
        )
    }

    func sources(for item: MediaItem, mode: PlaybackMode) async -> Result<[AddonStream], PlaybackError> {
        switch PlaybackRequest.streamQuery(for: item, mode: mode) {
        case .failure(let error):
            return .failure(error)
        case .success(let query):
            return await loadStreams(profile: query.profile, type: query.type, id: query.id)
                .map { $0.filter(\.isPlayable) }
        }
    }

    func sources(videoId: String, isAnime: Bool, mode: PlaybackMode) async -> Result<[AddonStream], PlaybackError> {
        switch PlaybackRequest.streamQuery(videoId: videoId, isAnime: isAnime, mode: mode) {
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

    func invalidatePendingPlay() {
        playGeneration += 1
        if state == .loading {
            state = .idle
        }
        dismissError()
    }

    func startNativeSession(
        videoURL: URL,
        title: String,
        position: Int?,
        entry: ResumeEntry?,
        episodeContext: EpisodeSessionContext? = nil,
        contentKey: String? = nil,
        metadata: NativeSessionMetadata? = nil,
        preferenceScope: TrackPreferenceScope = .global
    ) {
        beginNativeSession(
            videoURL: videoURL,
            title: title,
            position: position,
            entry: entry,
            episodeContext: episodeContext,
            contentKey: contentKey,
            metadata: metadata,
            preferenceScope: preferenceScope,
            context: nil
        )
    }

    private func beginNativeSession(
        videoURL: URL,
        title: String,
        position: Int?,
        entry: ResumeEntry?,
        episodeContext: EpisodeSessionContext?,
        contentKey: String?,
        metadata: NativeSessionMetadata?,
        preferenceScope: TrackPreferenceScope,
        context: NativePlaybackContext?
    ) {
        if let entry {
            progressStore.registerSession(
                videoURL: videoURL.absoluteString,
                entry: entry,
                episodeContext: episodeContext
            )
        }
        nativePosition = nil
        nativeDuration = nil
        lastCheckpoint = nil
        lastEndedNativePosition = nil
        resetNativeContext()
        nativeContext = context
        nativePreferenceScope = preferenceScope
        nativeSession = NativePlaybackSession(
            videoURL: videoURL,
            title: title,
            contentKey: contentKey,
            startSeconds: position,
            metadata: metadata,
            trackPreferences: trackPreferenceStore.preference(
                for: preferenceScope,
                profileID: progressStore.activeProfileID
            )
        )
        state = .idle
    }

    func switchNativeSource(videoURL: URL, stream: AddonStream? = nil) {
        guard var session = nativeSession, session.videoURL != videoURL else { return }
        progressStore.migrateSession(
            videoURL: session.videoURL.absoluteString,
            to: videoURL.absoluteString
        )
        session.videoURL = videoURL
        nativeSession = session
        guard let stream, var context = nativeContext else { return }
        let bingeGroup = stream.behaviorHints?.bingeGroup
        guard context.bingeGroup != bingeGroup else { return }
        context.bingeGroup = bingeGroup
        nativeContext = context
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedNext = nil
    }

    func setNativeSegments(_ segments: [NativeSkipSegment], for sessionID: UUID) {
        guard var session = nativeSession, session.id == sessionID, session.segments != segments else { return }
        session.segments = segments
        nativeSession = session
    }

    func recordTrackChoice(_ choice: TrackChoice, for sessionID: UUID) {
        guard nativeSession?.id == sessionID else { return }
        trackPreferenceStore.record(choice, scope: nativePreferenceScope, profileID: progressStore.activeProfileID)
    }

    var nativeUpNextEpisode: EpisodeItem? {
        guard let context = nativeContext, context.episode != nil else { return nil }
        return context.next
    }

    var hasNativeSources: Bool {
        nativeContext != nil
    }

    func nativeSourceOptions() async throws -> [NativeSourceOption] {
        guard let sessionID = nativeSession?.id, let context = nativeContext else {
            throw PlaybackError.noSources
        }
        let result: Result<[AddonStream], PlaybackError>
        if let episode = context.episode {
            result = await sources(videoId: episode.videoId, isAnime: context.item.isAnime, mode: context.mode)
        } else {
            result = await sources(for: context.item, mode: context.mode)
        }
        let streams = try result.get()
        guard let session = nativeSession, session.id == sessionID else { throw CancellationError() }
        nativeSourceStreams = streams
        return UpNextPlanner.sourceOptions(from: streams, current: session.videoURL)
    }

    func selectNativeSource(id: String) {
        guard let stream = nativeSourceStreams.first(where: { $0.playbackURL?.absoluteString == id }),
              let videoURL = stream.playbackURL else { return }
        switchNativeSource(videoURL: videoURL, stream: stream)
    }

    func advanceToNextEpisode() async {
        guard !isAdvancing,
              let session = nativeSession,
              let context = nativeContext,
              let episode = context.episode,
              let next = context.next else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        if let prefetchTask {
            await prefetchTask.value
        }
        let resolved: Result<AddonStream, PlaybackError>
        if let prefetched = prefetchedNext, prefetched.videoId == next.videoId {
            resolved = .success(prefetched.stream)
        } else {
            resolved = await nextEpisodeStream(next, context: context)
        }
        guard nativeSession?.id == session.id else { return }
        let stream: AddonStream
        let videoURL: URL
        switch resolved {
        case .failure(let error):
            completeNativeSession()
            state = .failed(error)
            return
        case .success(let found):
            guard let url = found.playbackURL else {
                completeNativeSession()
                state = .failed(.noSources)
                return
            }
            stream = found
            videoURL = url
        }
        let seriesId = PlaybackProgressStore.seriesKey(for: context.item) ?? episode.videoId
        finalizeNativeSession(session)
        progressStore.markEpisodeWatched(seriesId: seriesId, videoId: episode.videoId, next: Self.nextRef(next))
        startEpisodeSession(
            item: context.item,
            episode: next,
            next: context.timeline?.episodeAfter(next),
            timeline: context.timeline,
            mode: context.mode,
            stream: stream,
            videoURL: videoURL
        )
    }

    func updateNativePosition(_ seconds: Int) {
        guard let session = nativeSession, seconds > 0 else { return }
        nativePosition = seconds
        prefetchNextEpisodeIfNeeded(position: seconds)
        guard let last = lastCheckpoint else {
            lastCheckpoint = seconds
            return
        }
        guard abs(seconds - last) >= Self.checkpointInterval else { return }
        lastCheckpoint = seconds
        progressStore.checkpoint(
            videoURL: session.videoURL.absoluteString,
            position: seconds,
            duration: nativeDuration
        )
    }

    func updateNativeDuration(_ seconds: Int) {
        guard nativeSession != nil, seconds > 0 else { return }
        nativeDuration = seconds
    }

    func completeNativeSession() {
        guard let session = nativeSession else { return }
        nativeSession = nil
        finalizeNativeSession(session)
    }

    private func finalizeNativeSession(_ session: NativePlaybackSession) {
        let videoURL = session.videoURL.absoluteString
        if let position = nativePosition {
            progressStore.applyCallback(lastPlayedURL: videoURL, position: position, duration: nativeDuration)
        } else {
            progressStore.discardSession(videoURL: videoURL)
        }
        lastEndedNativePosition = nativePosition
        nativePosition = nil
        nativeDuration = nil
        lastCheckpoint = nil
        resetNativeContext()
    }

    private func resetNativeContext() {
        nativeContext = nil
        nativePreferenceScope = .global
        nativeSourceStreams = []
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedNext = nil
    }

    private func prefetchNextEpisodeIfNeeded(position: Int) {
        guard prefetchTask == nil,
              let sessionID = nativeSession?.id,
              let context = nativeContext,
              context.episode != nil,
              let next = context.next,
              UpNextPlanner.shouldPrefetch(position: position, duration: nativeDuration) else { return }
        prefetchTask = Task {
            let result = await nextEpisodeStream(next, context: context)
            guard !Task.isCancelled,
                  nativeSession?.id == sessionID,
                  nativeContext?.next?.videoId == next.videoId,
                  case .success(let stream) = result else { return }
            prefetchedNext = (next.videoId, stream)
        }
    }

    private func nextEpisodeStream(
        _ next: EpisodeItem,
        context: NativePlaybackContext
    ) async -> Result<AddonStream, PlaybackError> {
        let query: (profile: StreamProfile, type: String)
        switch PlaybackRequest.streamQuery(videoId: next.videoId, isAnime: context.item.isAnime, mode: context.mode) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            query = resolved
        }
        switch await loadStreams(profile: query.profile, type: query.type, id: next.videoId) {
        case .failure(let error):
            return .failure(error)
        case .success(let streams):
            guard let stream = UpNextPlanner.stream(in: streams, bingeGroup: context.bingeGroup) else {
                return .failure(.noSources)
            }
            return .success(stream)
        }
    }

    private func startEpisodeSession(
        item: MediaItem,
        episode: EpisodeItem,
        next: EpisodeItem?,
        timeline: EpisodeTimeline?,
        mode: PlaybackMode,
        stream: AddonStream,
        videoURL: URL
    ) {
        let seriesId = PlaybackProgressStore.seriesKey(for: item) ?? episode.videoId
        beginNativeSession(
            videoURL: videoURL,
            title: item.title,
            position: resumePosition(
                seriesId: seriesId,
                videoId: episode.videoId,
                runtimeMinutes: episode.runtimeMinutes
            ),
            entry: PlaybackRequest.resumeEntry(for: item, seriesId: seriesId, episode: episode),
            episodeContext: EpisodeSessionContext(
                seriesId: seriesId,
                videoId: episode.videoId,
                season: episode.season,
                episode: episode.episode,
                next: next.map(Self.nextRef)
            ),
            contentKey: episode.videoId,
            metadata: PlaybackRequest.sessionMetadata(
                for: item,
                subtitle: episode.title.isEmpty ? nil : episode.title,
                runtimeMinutes: episode.runtimeMinutes,
                seasonNumber: episode.season,
                episodeNumber: episode.episode
            ),
            preferenceScope: .series(seriesId),
            context: NativePlaybackContext(
                item: item,
                episode: episode,
                next: next,
                timeline: timeline,
                mode: mode,
                bingeGroup: stream.behaviorHints?.bingeGroup
            )
        )
    }

    private nonisolated static func nextRef(_ episode: EpisodeItem) -> NextEpisodeRef {
        NextEpisodeRef(
            videoId: episode.videoId,
            season: episode.season,
            episode: episode.episode,
            title: episode.title,
            runtimeMinutes: episode.runtimeMinutes
        )
    }

    private func beginPlay() -> Int {
        playGeneration += 1
        return playGeneration
    }

    private func isCurrentPlay(_ generation: Int) -> Bool {
        generation == playGeneration
    }

    private func openExternal(_ service: StreamingService, item: MediaItem, generation: Int) async {
        state = .loading
        let candidates = await titleURLs(for: service, item: item) + service.appURLs
        for url in candidates {
            guard isCurrentPlay(generation) else { return }
            if await UIApplication.shared.open(url) {
                if isCurrentPlay(generation) { state = .idle }
                return
            }
        }
        guard isCurrentPlay(generation) else { return }
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

    private func playViaInfuse(
        item: MediaItem,
        mode: PlaybackMode,
        engine: PlayerEngine,
        preferredStream: AddonStream?,
        generation: Int
    ) async {
        let query: (profile: StreamProfile, type: String, id: String)
        switch PlaybackRequest.streamQuery(for: item, mode: mode) {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let resolved):
            query = resolved
        }
        state = .loading
        let result = await loadStreams(profile: query.profile, type: query.type, id: query.id)
        guard isCurrentPlay(generation) else { return }
        let streams: [AddonStream]
        switch result {
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
        let entry = PlaybackRequest.resumeEntry(
            for: item,
            contentId: contentId,
            imdbId: PlaybackRequest.imdbId(for: item),
            runtimeMinutes: runtimeMinutes
        )
        if engine == .native {
            beginNativeSession(
                videoURL: videoURL,
                title: item.title,
                position: position,
                entry: entry,
                episodeContext: nil,
                contentKey: contentId,
                metadata: PlaybackRequest.sessionMetadata(for: item, subtitle: nil, runtimeMinutes: runtimeMinutes),
                preferenceScope: .global,
                context: NativePlaybackContext(
                    item: item,
                    episode: nil,
                    next: nil,
                    timeline: nil,
                    mode: mode,
                    bingeGroup: chosen.behaviorHints?.bingeGroup
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
            filename: PlaybackRequest.infuseFilename(for: item, filename: chosen.behaviorHints?.filename),
            positionSeconds: position
        )
        guard let url = InfuseURLBuilder.playURL(item: playItem) else {
            state = .failed(.openFailed)
            return
        }
        let videoURLString = videoURL.absoluteString
        progressStore.registerSession(videoURL: videoURLString, entry: entry)
        if await InfuseLauncher.open(url) {
            if isCurrentPlay(generation) { state = .idle }
        } else {
            progressStore.discardSession(videoURL: videoURLString)
            if isCurrentPlay(generation) { state = .failed(.openFailed) }
        }
    }

    private func playEpisodeViaInfuse(
        item: MediaItem,
        episode: EpisodeItem,
        next: EpisodeItem?,
        timeline: EpisodeTimeline?,
        mode: PlaybackMode,
        engine: PlayerEngine,
        preferredStream: AddonStream?,
        generation: Int
    ) async {
        let query: (profile: StreamProfile, type: String)
        switch PlaybackRequest.streamQuery(videoId: episode.videoId, isAnime: item.isAnime, mode: mode) {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let resolved):
            query = resolved
        }
        state = .loading
        let result = await loadStreams(profile: query.profile, type: query.type, id: episode.videoId)
        guard isCurrentPlay(generation) else { return }
        let streams: [AddonStream]
        switch result {
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
        if engine == .native {
            startEpisodeSession(
                item: item,
                episode: episode,
                next: next,
                timeline: timeline,
                mode: mode,
                stream: chosen,
                videoURL: videoURL
            )
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
        let entry = PlaybackRequest.resumeEntry(for: item, seriesId: seriesId, episode: episode)
        guard InfuseLauncher.isInstalled else {
            state = .failed(.infuseNotInstalled)
            return
        }
        let playItem = InfusePlayItem(
            videoURL: videoURL,
            filename: PlaybackRequest.infuseFilename(item: item, episode: episode, filename: chosen.behaviorHints?.filename),
            positionSeconds: position
        )
        guard let url = InfuseURLBuilder.playURL(item: playItem) else {
            state = .failed(.openFailed)
            return
        }
        let videoURLString = videoURL.absoluteString
        progressStore.registerSession(videoURL: videoURLString, entry: entry, episodeContext: context)
        if await InfuseLauncher.open(url) {
            if isCurrentPlay(generation) { state = .idle }
        } else {
            progressStore.discardSession(videoURL: videoURLString)
            if isCurrentPlay(generation) { state = .failed(.openFailed) }
        }
    }

    private func loadStreams(profile: StreamProfile, type: String, id: String) async -> Result<[AddonStream], PlaybackError> {
        do {
            return .success(try await fetchStreams(profile: profile, type: type, id: id))
        } catch let error as StreamsAPIError {
            return .failure(PlaybackRequest.playbackError(for: error))
        } catch {
            return .failure(.network)
        }
    }

    private func fetchStreams(profile: StreamProfile, type: String, id: String) async throws -> [AddonStream] {
        let api = self.api
        return try await cache.value(for: "\(profile.rawValue)|\(type)|\(id)") {
            try await api.streams(profile: profile, type: type, id: id)
        }
    }

    private func resumePosition(for contentId: String, runtimeMinutes: Int?) -> Int? {
        ResumePolicy.startSeconds(position: progressStore.position(for: contentId), runtimeMinutes: runtimeMinutes)
    }

    private func resumePosition(seriesId: String, videoId: String, runtimeMinutes: Int?) -> Int? {
        guard let entry = progressStore.entry(forSeries: seriesId), entry.videoId == videoId else { return nil }
        return ResumePolicy.startSeconds(position: entry.positionSeconds, runtimeMinutes: runtimeMinutes)
    }

    nonisolated static func streamRequest(videoId: String, isAnime: Bool) -> (type: String, profile: StreamProfile?) {
        PlaybackRequest.streamRequest(videoId: videoId, isAnime: isAnime)
    }

    nonisolated static func infuseFilename(item: MediaItem, episode: EpisodeItem, filename: String?) -> String {
        PlaybackRequest.infuseFilename(item: item, episode: episode, filename: filename)
    }
}
