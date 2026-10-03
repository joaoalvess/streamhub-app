import Foundation
import Testing
@testable import StreamHub

@MainActor
struct MyListStoreTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "MyListStoreTests-\(UUID().uuidString)"
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
            posterURL: URL(string: "https://img.example/\(contentId).jpg"),
            backdropURL: nil,
            synopsis: "",
            year: 2020
        )
    }

    @Test func toggleAddsMostRecentFirst() throws {
        let store = MyListStore(defaults: try makeDefaults())
        store.toggle(item("tt1"))
        store.toggle(item("tt2"))
        #expect(store.entries.map(\.contentId) == ["tt2", "tt1"])
        #expect(store.contains(item("tt1")))
        #expect(store.contains(item("tt2")))
    }

    @Test func toggleRemovesExistingEntryKeepingOrder() throws {
        let store = MyListStore(defaults: try makeDefaults())
        store.toggle(item("tt1"))
        store.toggle(item("tt2"))
        store.toggle(item("tt3"))
        store.toggle(item("tt2"))
        #expect(store.entries.map(\.contentId) == ["tt3", "tt1"])
        #expect(!store.contains(item("tt2")))
    }

    @Test func toggleAgainAfterRemovalMovesItemToFront() throws {
        let store = MyListStore(defaults: try makeDefaults())
        store.toggle(item("tt1"))
        store.toggle(item("tt2"))
        store.toggle(item("tt1"))
        store.toggle(item("tt1"))
        #expect(store.entries.map(\.contentId) == ["tt1", "tt2"])
    }

    @Test func removeByContentIdDropsEntry() throws {
        let store = MyListStore(defaults: try makeDefaults())
        store.toggle(item("tt1"))
        store.toggle(item("kitsu:11", kind: .anime))
        store.remove(contentId: "kitsu:11")
        #expect(store.entries.map(\.contentId) == ["tt1"])
    }

    @Test func usesImdbIdWhenContentIdIsMissing() throws {
        let store = MyListStore(defaults: try makeDefaults())
        let imdbOnly = MediaItem(
            imdbId: "tt7", title: "X", kind: .series, genres: [],
            posterURL: nil, backdropURL: nil, synopsis: "", year: 2021
        )
        store.toggle(imdbOnly)
        #expect(store.entries.map(\.contentId) == ["tt7"])
        #expect(store.contains(imdbOnly))
    }

    @Test func toggleIgnoresItemWithoutStableId() throws {
        let store = MyListStore(defaults: try makeDefaults())
        let orphan = MediaItem(
            title: "X", kind: .movie, genres: [],
            posterURL: nil, backdropURL: nil, synopsis: "", year: 0
        )
        store.toggle(orphan)
        #expect(store.entries.isEmpty)
        #expect(!store.contains(orphan))
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        let first = MyListStore(defaults: defaults)
        first.setActiveProfile(profile)
        first.toggle(item("tt1"))
        first.toggle(item("tt2"))
        let second = MyListStore(defaults: defaults)
        second.setActiveProfile(profile)
        #expect(second.entries.map(\.contentId) == ["tt2", "tt1"])
        #expect(second.entries.first?.posterURL == URL(string: "https://img.example/tt2.jpg"))
    }

    @Test func isolatesEntriesPerProfile() throws {
        let defaults = try makeDefaults()
        let profileA = UUID()
        let profileB = UUID()
        let store = MyListStore(defaults: defaults)
        store.setActiveProfile(profileA)
        store.toggle(item("tt1"))
        store.setActiveProfile(profileB)
        #expect(store.entries.isEmpty)
        #expect(!store.contains(item("tt1")))
        store.toggle(item("tt2"))
        store.setActiveProfile(profileA)
        #expect(store.entries.map(\.contentId) == ["tt1"])
    }

    @Test func removeDataClearsOnlyThatProfile() throws {
        let defaults = try makeDefaults()
        let profileA = UUID()
        let profileB = UUID()
        let store = MyListStore(defaults: defaults)
        store.setActiveProfile(profileB)
        store.toggle(item("tt9"))
        store.setActiveProfile(profileA)
        store.toggle(item("tt1"))
        store.removeData(for: profileA)
        #expect(store.entries.isEmpty)
        let reloaded = MyListStore(defaults: defaults)
        reloaded.setActiveProfile(profileA)
        #expect(reloaded.entries.isEmpty)
        reloaded.setActiveProfile(profileB)
        #expect(reloaded.entries.map(\.contentId) == ["tt9"])
    }

    @Test func adoptLegacyDataMovesEntriesToProfileOnce() throws {
        let defaults = try makeDefaults()
        let legacy = MyListStore(defaults: defaults)
        legacy.toggle(item("tt1"))

        let store = MyListStore(defaults: defaults)
        let profile = UUID()
        store.adoptLegacyDataIfNeeded(for: profile)
        store.setActiveProfile(profile)
        #expect(store.entries.map(\.contentId) == ["tt1"])

        store.setActiveProfile(nil)
        #expect(store.entries.isEmpty)
    }

    @Test func rebuiltMediaItemKeepsIdentity() throws {
        let store = MyListStore(defaults: try makeDefaults())
        store.toggle(item("kitsu:11", kind: .anime, title: "Naruto"))
        let entry = try #require(store.entries.first)
        let rebuilt = MediaItem(myList: entry)
        #expect(rebuilt.contentId == "kitsu:11")
        #expect(rebuilt.kind == .anime)
        #expect(rebuilt.isAnime)
        #expect(rebuilt.title == "Naruto")
        #expect(store.contains(rebuilt))
    }
}
