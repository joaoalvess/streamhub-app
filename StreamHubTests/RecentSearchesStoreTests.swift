import Foundation
import Testing
@testable import StreamHub

@MainActor
struct RecentSearchesStoreTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "RecentSearchesStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func item(_ contentId: String, kind: MediaItem.Kind = .movie, title: String = "T") -> MediaItem {
        MediaItem(
            contentId: contentId,
            imdbId: contentId.hasPrefix("tt") ? contentId : nil,
            title: title,
            kind: kind,
            genres: ["Drama"],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2020
        )
    }

    @Test func recordInsertsMostRecentFirst() throws {
        let store = RecentSearchesStore(defaults: try makeDefaults())
        store.record(item("tt1"))
        store.record(item("tt2"))
        #expect(store.entries.map(\.contentId) == ["tt2", "tt1"])
    }

    @Test func recordDedupesByStableKeyMovingToFront() throws {
        let store = RecentSearchesStore(defaults: try makeDefaults())
        store.record(item("tt1"))
        store.record(item("tt2"))
        store.record(item("tt1"))
        #expect(store.entries.map(\.contentId) == ["tt1", "tt2"])
        #expect(store.entries.count == 2)
    }

    @Test func capsEntriesAtTen() throws {
        let store = RecentSearchesStore(defaults: try makeDefaults())
        for index in 1...12 {
            store.record(item("tt\(index)"))
        }
        #expect(store.entries.count == 10)
        #expect(store.entries.first?.contentId == "tt12")
        #expect(!store.entries.contains { $0.contentId == "tt1" || $0.contentId == "tt2" })
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        let first = RecentSearchesStore(defaults: defaults)
        first.setActiveProfile(profile)
        first.record(item("tt1"))
        let second = RecentSearchesStore(defaults: defaults)
        second.setActiveProfile(profile)
        #expect(second.entries.map(\.contentId) == ["tt1"])
    }

    @Test func isolatesEntriesPerProfile() throws {
        let defaults = try makeDefaults()
        let profileA = UUID()
        let profileB = UUID()
        let store = RecentSearchesStore(defaults: defaults)
        store.setActiveProfile(profileA)
        store.record(item("tt1"))
        store.setActiveProfile(profileB)
        #expect(store.entries.isEmpty)
        store.record(item("tt2"))
        store.setActiveProfile(profileA)
        #expect(store.entries.map(\.contentId) == ["tt1"])
    }

    @Test func removeDataClearsProfile() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        let store = RecentSearchesStore(defaults: defaults)
        store.setActiveProfile(profile)
        store.record(item("tt1"))
        store.removeData(for: profile)
        #expect(store.entries.isEmpty)
        let reloaded = RecentSearchesStore(defaults: defaults)
        reloaded.setActiveProfile(profile)
        #expect(reloaded.entries.isEmpty)
    }

    @Test func recordIgnoresItemWithoutStableId() throws {
        let store = RecentSearchesStore(defaults: try makeDefaults())
        let orphan = MediaItem(
            title: "X", kind: .movie, genres: [],
            posterURL: nil, backdropURL: nil, synopsis: "", year: 0
        )
        store.record(orphan)
        #expect(store.entries.isEmpty)
    }

    @Test func rebuiltMediaItemKeepsPlaybackIdentity() throws {
        let store = RecentSearchesStore(defaults: try makeDefaults())
        store.record(item("kitsu:11", kind: .anime, title: "Naruto"))
        let entry = try #require(store.entries.first)
        let rebuilt = MediaItem(recent: entry)
        #expect(rebuilt.contentId == "kitsu:11")
        #expect(rebuilt.kind == .anime)
        #expect(rebuilt.isAnime)
        #expect(rebuilt.title == "Naruto")
    }
}
