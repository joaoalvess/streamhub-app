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

@Observable
final class PlaybackProgressStore {
    private struct SessionRecord: Codable {
        let entry: ResumeEntry
        let previousPosition: Int?
        let startedAt: Date
    }

    private static let entriesKey = "playback.resume.v1"
    private static let sessionsKey = "playback.sessions.v1"
    private static let maxEntries = 20
    private static let maxSessions = 5
    private static let sessionTTL: TimeInterval = 86_400
    private static let completionThreshold = 0.92

    private(set) var entries: [ResumeEntry] = []
    private var sessions: [String: SessionRecord] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load([ResumeEntry].self, key: Self.entriesKey, defaults: defaults) ?? []
        let stored = Self.load([String: SessionRecord].self, key: Self.sessionsKey, defaults: defaults) ?? [:]
        sessions = stored.filter { Date().timeIntervalSince($0.value.startedAt) < Self.sessionTTL }
    }

    func position(for contentId: String) -> Int? {
        entries.first { $0.contentId == contentId }?.positionSeconds
    }

    func upsert(_ entry: ResumeEntry) {
        entries.removeAll { $0.contentId == entry.contentId }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        persist()
    }

    func registerSession(videoURL: String, entry: ResumeEntry) {
        let previous = position(for: entry.contentId)
        var optimistic = entry
        optimistic.positionSeconds = previous ?? 0
        optimistic.updatedAt = Date()
        sessions[videoURL] = SessionRecord(
            entry: optimistic,
            previousPosition: previous,
            startedAt: Date()
        )
        if sessions.count > Self.maxSessions {
            let newest = sessions
                .sorted { $0.value.startedAt > $1.value.startedAt }
                .prefix(Self.maxSessions)
            sessions = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        upsert(optimistic)
    }

    func applyCallback(lastPlayedURL: String, position: Int) {
        guard let record = sessions.removeValue(forKey: lastPlayedURL) else { return }
        var entry = record.entry
        entry.positionSeconds = position
        entry.updatedAt = Date()
        if let progress = entry.progress, progress >= Self.completionThreshold {
            remove(contentId: entry.contentId)
        } else {
            upsert(entry)
        }
    }

    func discardSession(videoURL: String) {
        guard let record = sessions.removeValue(forKey: videoURL) else { return }
        if let previous = record.previousPosition {
            var entry = record.entry
            entry.positionSeconds = previous
            entry.updatedAt = Date()
            upsert(entry)
        } else {
            remove(contentId: record.entry.contentId)
        }
    }

    func remove(contentId: String) {
        entries.removeAll { $0.contentId == contentId }
        persist()
    }

    private func persist() {
        Self.save(entries, key: Self.entriesKey, defaults: defaults)
        Self.save(sessions, key: Self.sessionsKey, defaults: defaults)
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
