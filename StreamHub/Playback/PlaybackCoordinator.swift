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

    enum PlaybackError: Equatable {
        case missingImdbId
        case notConfigured
        case noSources
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
    let progressStore: PlaybackProgressStore

    private let api: StreamsAPI
    private var cache: [String: (fetchedAt: Date, streams: [AddonStream])] = [:]
    private var inFlight: [String: Task<[AddonStream], any Error>] = [:]
    private static let cacheTTL: TimeInterval = 60

    init(api: StreamsAPI = StreamsAPI(), progressStore: PlaybackProgressStore = PlaybackProgressStore()) {
        self.api = api
        self.progressStore = progressStore
    }

    func route(for item: MediaItem) -> Route {
        if let service = item.streamingSource, service.isSubscribed {
            return .externalService(service)
        }
        return .infuse
    }

    func play(item: MediaItem, mode: PlaybackMode) async {
        guard state != .loading, item.kind == .movie || item.isAnime else { return }
        switch route(for: item) {
        case .externalService(let service):
            await openExternal(service)
        case .infuse:
            await playViaInfuse(item: item, mode: mode)
        }
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

    private func openExternal(_ service: StreamingService) async {
        state = .loading
        for url in service.appURLs {
            if await UIApplication.shared.open(url) {
                state = .idle
                return
            }
        }
        state = .failed(.serviceOpenFailed(service.displayName))
    }

    private func playViaInfuse(item: MediaItem, mode: PlaybackMode) async {
        let profile: StreamProfile
        let type: String
        let id: String
        if item.isAnime {
            guard let animeId = Self.animeStreamId(for: item) else {
                state = .failed(.missingImdbId)
                return
            }
            profile = .anime
            type = "anime"
            id = animeId
        } else {
            guard let modeProfile = StreamProfile(mode: mode) else {
                state = .failed(.enhancedUnavailable)
                return
            }
            guard let imdbId = Self.imdbId(for: item) else {
                state = .failed(.missingImdbId)
                return
            }
            profile = modeProfile
            type = "movie"
            id = imdbId
        }
        state = .loading
        let streams: [AddonStream]
        do {
            streams = try await fetchStreams(profile: profile, type: type, id: id)
        } catch let error as StreamsAPIError {
            state = .failed(Self.playbackError(for: error))
            return
        } catch {
            state = .failed(.network)
            return
        }
        guard let chosen = streams.first(where: \.isPlayable),
              let videoURL = chosen.playbackURL else {
            state = .failed(.noSources)
            return
        }
        guard InfuseLauncher.isInstalled else {
            state = .failed(.infuseNotInstalled)
            return
        }
        let contentId = item.contentId ?? id
        let runtimeMinutes = Self.runtimeMinutes(from: item.runtime)
        let playItem = InfusePlayItem(
            videoURL: videoURL,
            filename: Self.infuseFilename(for: item, filename: chosen.behaviorHints?.filename),
            positionSeconds: resumePosition(for: contentId, runtimeMinutes: runtimeMinutes)
        )
        guard let url = InfuseURLBuilder.playURL(item: playItem) else {
            state = .failed(.openFailed)
            return
        }
        let videoURLString = videoURL.absoluteString
        progressStore.registerSession(
            videoURL: videoURLString,
            entry: Self.resumeEntry(
                for: item,
                contentId: contentId,
                imdbId: Self.imdbId(for: item),
                runtimeMinutes: runtimeMinutes
            )
        )
        if await InfuseLauncher.open(url) {
            state = .idle
        } else {
            progressStore.discardSession(videoURL: videoURLString)
            state = .failed(.openFailed)
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

    private static func runtimeMinutes(from runtime: String?) -> Int? {
        guard let runtime = runtime?.lowercased() else { return nil }
        if let match = runtime.firstMatch(of: #/(\d+)\s*h\s*(\d+)?/#) {
            let hours = Int(match.1) ?? 0
            let minutes = match.2.flatMap { Int($0) } ?? 0
            return hours * 60 + minutes
        }
        guard let match = runtime.firstMatch(of: #/(\d+)/#) else { return nil }
        return Int(match.1)
    }

    private static func infuseFilename(for item: MediaItem, filename: String?) -> String {
        let knownExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "ts", "webm", "mov"]
        let ext = filename
            .map { ($0 as NSString).pathExtension.lowercased() }
            .flatMap { knownExtensions.contains($0) ? $0 : nil }
            ?? "mkv"
        guard item.year > 0 else { return "\(item.title).\(ext)" }
        return "\(item.title) (\(item.year)).\(ext)"
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
            serviceCode: item.streamingSource?.rawValue
        )
    }
}
