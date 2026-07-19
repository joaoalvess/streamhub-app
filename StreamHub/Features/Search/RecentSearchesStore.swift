import Foundation
import Observation

nonisolated struct RecentSearchEntry: Codable, Hashable {
    let contentId: String
    let imdbId: String?
    let kind: String
    let title: String
    let posterURL: URL?
    let backdropURL: URL?
    let logoURL: URL?
    let genres: [String]
    let year: Int
    let recordedAt: Date
}

@Observable
final class RecentSearchesStore {
    private static let baseKey = "search.recents.v1"
    private static let maxEntries = 10

    private(set) var entries: [RecentSearchEntry] = []
    private var activeProfileID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load(key: Self.entriesKey(for: nil), defaults: defaults)
    }

    func record(_ item: MediaItem) {
        guard let key = item.contentId ?? item.imdbId else { return }
        let entry = RecentSearchEntry(
            contentId: key,
            imdbId: item.imdbId,
            kind: item.kind.rawValue,
            title: item.title,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            logoURL: item.logoURL,
            genres: item.genres,
            year: item.year,
            recordedAt: Date()
        )
        entries = Self.upserted(entry, into: entries)
        persist()
    }

    func setActiveProfile(_ id: UUID?) {
        guard id != activeProfileID else { return }
        activeProfileID = id
        entries = Self.load(key: Self.entriesKey(for: id), defaults: defaults)
    }

    func removeData(for profileID: UUID) {
        defaults.removeObject(forKey: Self.entriesKey(for: profileID))
        if activeProfileID == profileID { entries = [] }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.entriesKey(for: activeProfileID))
    }

    private static func entriesKey(for id: UUID?) -> String {
        guard let id else { return baseKey }
        return "\(baseKey).\(id.uuidString)"
    }

    private static func load(key: String, defaults: UserDefaults) -> [RecentSearchEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentSearchEntry].self, from: data)) ?? []
    }

    private static func upserted(_ entry: RecentSearchEntry, into entries: [RecentSearchEntry]) -> [RecentSearchEntry] {
        var result = entries.filter { $0.contentId != entry.contentId }
        result.insert(entry, at: 0)
        if result.count > maxEntries {
            result = Array(result.prefix(maxEntries))
        }
        return result
    }
}

nonisolated extension MediaItem {
    init(recent entry: RecentSearchEntry) {
        self.init(
            contentId: entry.contentId,
            imdbId: entry.imdbId,
            title: entry.title,
            kind: MediaItem.Kind(rawValue: entry.kind) ?? .movie,
            genres: entry.genres,
            posterURL: entry.posterURL,
            backdropURL: entry.backdropURL,
            logoURL: entry.logoURL,
            synopsis: "",
            year: entry.year
        )
    }
}
