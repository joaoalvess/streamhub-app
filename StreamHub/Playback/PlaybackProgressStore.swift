import Foundation
import Observation

nonisolated struct ResumeEntry: Codable, Hashable {
    let contentId: String
    let imdbId: String?
    let title: String
    let year: Int
    let posterURL: URL?
    let backdropURL: URL?
    let logoURL: URL?
    let runtimeMinutes: Int?
    var positionSeconds: Int
    var updatedAt: Date
    let serviceCode: String?
    let synopsis: String?
    let genres: [String]?
    let mediaKind: String?
    let metaId: String?
    var videoId: String?
    var season: Int?
    var episode: Int?
    var episodeTitle: String?

    init(
        contentId: String,
        imdbId: String?,
        title: String,
        year: Int,
        posterURL: URL?,
        backdropURL: URL?,
        logoURL: URL?,
        runtimeMinutes: Int?,
        positionSeconds: Int,
        updatedAt: Date,
        serviceCode: String?,
        synopsis: String?,
        genres: [String]?,
        mediaKind: String? = nil,
        metaId: String? = nil,
        videoId: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil
    ) {
        self.contentId = contentId
        self.imdbId = imdbId
        self.title = title
        self.year = year
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.runtimeMinutes = runtimeMinutes
        self.positionSeconds = positionSeconds
        self.updatedAt = updatedAt
        self.serviceCode = serviceCode
        self.synopsis = synopsis
        self.genres = genres
        self.mediaKind = mediaKind
        self.metaId = metaId
        self.videoId = videoId
        self.season = season
        self.episode = episode
        self.episodeTitle = episodeTitle
    }

    var episodeCode: String? {
        guard let season, let episode else { return nil }
        return "T\(season)E\(episode)"
    }

    var progress: Double? {
        guard let runtimeMinutes, runtimeMinutes > 0 else { return nil }
        return min(1, max(0, Double(positionSeconds) / Double(runtimeMinutes * 60)))
    }

    var remainingLabel: String? {
        guard let runtimeMinutes, runtimeMinutes > 0, positionSeconds > 0 else { return nil }
        let remaining = max(0, runtimeMinutes - positionSeconds / 60)
        return "Restam \(remaining) min"
    }
}

nonisolated struct EpisodeSessionContext: Codable, Hashable, Sendable {
    let seriesId: String
    let videoId: String
    let season: Int
    let episode: Int
    let next: NextEpisodeRef?
}

nonisolated struct NextEpisodeRef: Codable, Hashable, Sendable {
    let videoId: String
    let season: Int
    let episode: Int
    let title: String?
    let runtimeMinutes: Int?
}

nonisolated struct WatchedRecord: Codable, Hashable, Sendable {
    var videoIds: Set<String>
    var updatedAt: Date
}

@Observable
final class PlaybackProgressStore {
    private struct SessionRecord: Codable {
        let entry: ResumeEntry
        let previousEntry: ResumeEntry?
        let startedAt: Date
        var profileID: UUID?
        let episodeContext: EpisodeSessionContext?
    }

    private enum CallbackResolution {
        case remove(String)
        case upsert(ResumeEntry)
    }

    private static let legacyEntriesKey = "playback.resume.v1"
    private static let legacyWatchedKey = "playback.watched.v1"
    private static let sessionsKey = "playback.sessions.v1"

    private static func entriesKey(for id: UUID?) -> String {
        guard let id else { return legacyEntriesKey }
        return "\(legacyEntriesKey).\(id.uuidString)"
    }
    private static func watchedKey(for id: UUID?) -> String {
        guard let id else { return legacyWatchedKey }
        return "\(legacyWatchedKey).\(id.uuidString)"
    }
    private static let maxEntries = 20
    private static let maxSessions = 5
    private static let maxWatchedSeries = 40
    private static let sessionTTL: TimeInterval = 86_400
    private static let completionThreshold = 0.92

    private(set) var entries: [ResumeEntry] = []
    private(set) var activeProfileID: UUID?
    private var sessions: [String: SessionRecord] = [:]
    private var watched: [String: WatchedRecord] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load([ResumeEntry].self, key: Self.entriesKey(for: nil), defaults: defaults) ?? []
        watched = Self.load([String: WatchedRecord].self, key: Self.watchedKey(for: nil), defaults: defaults) ?? [:]
        let stored = Self.load([String: SessionRecord].self, key: Self.sessionsKey, defaults: defaults) ?? [:]
        sessions = stored.filter { Date().timeIntervalSince($0.value.startedAt) < Self.sessionTTL }
    }

    nonisolated static func seriesKey(for item: MediaItem) -> String? {
        item.imdbId ?? item.contentId
    }

    func position(for contentId: String) -> Int? {
        entries.first { $0.contentId == contentId }?.positionSeconds
    }

    func upsert(_ entry: ResumeEntry) {
        entries = Self.upserted(entry, into: entries)
        persistEntries()
    }

    func registerSession(videoURL: String, entry: ResumeEntry, episodeContext: EpisodeSessionContext? = nil) {
        let current = entries.first { $0.contentId == entry.contentId }
        var optimistic = entry
        optimistic.positionSeconds = current?.videoId == entry.videoId ? (current?.positionSeconds ?? 0) : 0
        optimistic.updatedAt = Date()
        sessions[videoURL] = SessionRecord(
            entry: optimistic,
            previousEntry: current,
            startedAt: Date(),
            profileID: activeProfileID,
            episodeContext: episodeContext
        )
        if sessions.count > Self.maxSessions {
            let newest = sessions
                .sorted { $0.value.startedAt > $1.value.startedAt }
                .prefix(Self.maxSessions)
            sessions = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        upsert(optimistic)
        persistSessions()
    }

    func applyCallback(lastPlayedURL: String, position: Int) {
        guard let record = sessions.removeValue(forKey: lastPlayedURL) else { return }
        var entry = record.entry
        entry.positionSeconds = position
        entry.updatedAt = Date()
        let owner = record.profileID ?? activeProfileID
        let completed = entry.progress.map { $0 >= Self.completionThreshold } ?? false
        if completed, let context = record.episodeContext {
            markWatched(seriesId: context.seriesId, videoId: context.videoId, owner: owner)
        }
        let resolution = Self.callbackResolution(
            entry: entry,
            completed: completed,
            context: record.episodeContext,
            previousEntry: record.previousEntry
        )
        apply(resolution, owner: owner)
        persistSessions()
    }

    func discardSession(videoURL: String) {
        guard let record = sessions.removeValue(forKey: videoURL) else { return }
        let owner = record.profileID ?? activeProfileID
        let resolution: CallbackResolution
        if var restored = record.previousEntry {
            restored.updatedAt = Date()
            resolution = .upsert(restored)
        } else {
            resolution = .remove(record.entry.contentId)
        }
        apply(resolution, owner: owner)
        persistSessions()
    }

    private func apply(_ resolution: CallbackResolution, owner: UUID?) {
        if owner == activeProfileID {
            switch resolution {
            case .remove(let contentId):
                remove(contentId: contentId)
            case .upsert(let entry):
                upsert(entry)
            }
        } else {
            updateStored(for: owner) { stored in
                switch resolution {
                case .remove(let contentId):
                    return stored.filter { $0.contentId != contentId }
                case .upsert(let entry):
                    return Self.upserted(entry, into: stored)
                }
            }
        }
    }

    private static func callbackResolution(
        entry: ResumeEntry,
        completed: Bool,
        context: EpisodeSessionContext?,
        previousEntry: ResumeEntry?
    ) -> CallbackResolution {
        guard completed else { return .upsert(entry) }
        guard let context else { return .remove(entry.contentId) }
        if let next = context.next {
            return .upsert(Self.advanced(entry, to: next))
        }
        if context.season == 0, var restored = previousEntry, restored.videoId != context.videoId {
            restored.updatedAt = Date()
            return .upsert(restored)
        }
        return .remove(entry.contentId)
    }

    private static func advanced(_ entry: ResumeEntry, to next: NextEpisodeRef) -> ResumeEntry {
        ResumeEntry(
            contentId: entry.contentId,
            imdbId: entry.imdbId,
            title: entry.title,
            year: entry.year,
            posterURL: entry.posterURL,
            backdropURL: entry.backdropURL,
            logoURL: entry.logoURL,
            runtimeMinutes: next.runtimeMinutes,
            positionSeconds: 0,
            updatedAt: Date(),
            serviceCode: entry.serviceCode,
            synopsis: entry.synopsis,
            genres: entry.genres,
            mediaKind: entry.mediaKind,
            metaId: entry.metaId,
            videoId: next.videoId,
            season: next.season,
            episode: next.episode,
            episodeTitle: next.title
        )
    }

    func watchedVideoIds(seriesId: String) -> Set<String> {
        watched[seriesId]?.videoIds ?? []
    }

    func isWatched(seriesId: String, videoId: String) -> Bool {
        watched[seriesId]?.videoIds.contains(videoId) ?? false
    }

    func markWatched(seriesId: String, videoId: String) {
        watched = Self.marking(watched, seriesId: seriesId, videoId: videoId)
        persistWatched()
    }

    private func markWatched(seriesId: String, videoId: String, owner: UUID?) {
        if owner == activeProfileID {
            markWatched(seriesId: seriesId, videoId: videoId)
            return
        }
        let key = Self.watchedKey(for: owner)
        let stored = Self.load([String: WatchedRecord].self, key: key, defaults: defaults) ?? [:]
        Self.save(Self.marking(stored, seriesId: seriesId, videoId: videoId), key: key, defaults: defaults)
    }

    private static func marking(
        _ map: [String: WatchedRecord],
        seriesId: String,
        videoId: String
    ) -> [String: WatchedRecord] {
        var result = map
        var record = result[seriesId] ?? WatchedRecord(videoIds: [], updatedAt: Date())
        record.videoIds.insert(videoId)
        record.updatedAt = Date()
        result[seriesId] = record
        if result.count > maxWatchedSeries {
            let newest = result
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(maxWatchedSeries)
            result = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        return result
    }

    func remove(contentId: String) {
        entries.removeAll { $0.contentId == contentId }
        persistEntries()
    }

    func setActiveProfile(_ id: UUID?) {
        guard id != activeProfileID else { return }
        activeProfileID = id
        entries = Self.load([ResumeEntry].self, key: Self.entriesKey(for: id), defaults: defaults) ?? []
        watched = Self.load([String: WatchedRecord].self, key: Self.watchedKey(for: id), defaults: defaults) ?? [:]
    }

    func adoptLegacyDataIfNeeded(for profileID: UUID) {
        let targetKey = Self.entriesKey(for: profileID)
        guard defaults.data(forKey: targetKey) == nil,
              let legacy = defaults.data(forKey: Self.legacyEntriesKey) else { return }
        defaults.set(legacy, forKey: targetKey)
        defaults.removeObject(forKey: Self.legacyEntriesKey)
        if activeProfileID == profileID {
            entries = Self.load([ResumeEntry].self, key: targetKey, defaults: defaults) ?? []
        }
    }

    func removeData(for profileID: UUID) {
        defaults.removeObject(forKey: Self.entriesKey(for: profileID))
        defaults.removeObject(forKey: Self.watchedKey(for: profileID))
        sessions = sessions.filter { $0.value.profileID != profileID }
        persistSessions()
        if activeProfileID == profileID {
            entries = []
            watched = [:]
        }
    }

    private func updateStored(for owner: UUID?, _ transform: ([ResumeEntry]) -> [ResumeEntry]) {
        let key = Self.entriesKey(for: owner)
        let stored = Self.load([ResumeEntry].self, key: key, defaults: defaults) ?? []
        Self.save(transform(stored), key: key, defaults: defaults)
    }

    private func persistEntries() {
        Self.save(entries, key: Self.entriesKey(for: activeProfileID), defaults: defaults)
    }

    private func persistSessions() {
        Self.save(sessions, key: Self.sessionsKey, defaults: defaults)
    }

    private func persistWatched() {
        Self.save(watched, key: Self.watchedKey(for: activeProfileID), defaults: defaults)
    }

    private static func upserted(_ entry: ResumeEntry, into entries: [ResumeEntry]) -> [ResumeEntry] {
        var result = entries.filter { $0.contentId != entry.contentId }
        result.insert(entry, at: 0)
        if result.count > maxEntries {
            result = Array(result.prefix(maxEntries))
        }
        return result
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
