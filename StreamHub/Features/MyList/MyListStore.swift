import Foundation
import Observation

nonisolated struct MyListEntry: Codable, Hashable {
    let contentId: String
    let imdbId: String?
    let kind: String
    let title: String
    let posterURL: URL?
    let backdropURL: URL?
    let logoURL: URL?
    let genres: [String]
    let year: Int
    let addedAt: Date
}

@Observable
final class MyListStore {
    private static let baseKey = "mylist.v1"

    private(set) var entries: [MyListEntry] = []
    private var activeProfileID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.load(key: Self.entriesKey(for: nil), defaults: defaults)
    }

    func contains(_ item: MediaItem) -> Bool {
        guard let key = Self.identity(of: item) else { return false }
        return entries.contains { $0.contentId == key }
    }

    func toggle(_ item: MediaItem) {
        guard let key = Self.identity(of: item) else { return }
        if entries.contains(where: { $0.contentId == key }) {
            remove(contentId: key)
            return
        }
        let entry = MyListEntry(
            contentId: key,
            imdbId: item.imdbId,
            kind: item.kind.rawValue,
            title: item.title,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            logoURL: item.logoURL,
            genres: item.genres,
            year: item.year,
            addedAt: Date()
        )
        entries.insert(entry, at: 0)
        persist()
    }

    func remove(contentId: String) {
        entries.removeAll { $0.contentId == contentId }
        persist()
    }

    func setActiveProfile(_ id: UUID?) {
        guard id != activeProfileID else { return }
        activeProfileID = id
        entries = Self.load(key: Self.entriesKey(for: id), defaults: defaults)
    }

    func adoptLegacyDataIfNeeded(for profileID: UUID) {
        let targetKey = Self.entriesKey(for: profileID)
        guard defaults.data(forKey: targetKey) == nil,
              let legacy = defaults.data(forKey: Self.baseKey) else { return }
        defaults.set(legacy, forKey: targetKey)
        defaults.removeObject(forKey: Self.baseKey)
        if activeProfileID == profileID {
            entries = Self.load(key: targetKey, defaults: defaults)
        }
    }

    func removeData(for profileID: UUID) {
        defaults.removeObject(forKey: Self.entriesKey(for: profileID))
        if activeProfileID == profileID { entries = [] }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.entriesKey(for: activeProfileID))
    }

    private static func identity(of item: MediaItem) -> String? {
        item.contentId ?? item.imdbId
    }

    private static func entriesKey(for id: UUID?) -> String {
        guard let id else { return baseKey }
        return "\(baseKey).\(id.uuidString)"
    }

    private static func load(key: String, defaults: UserDefaults) -> [MyListEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MyListEntry].self, from: data)) ?? []
    }
}

nonisolated extension MediaItem {
    init(myList entry: MyListEntry) {
        self.init(
            id: Self.stableID(for: "mylist:\(entry.contentId)"),
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
