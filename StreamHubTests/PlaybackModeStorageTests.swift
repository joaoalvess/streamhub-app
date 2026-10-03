import Foundation
import Testing
@testable import StreamHub

struct PlaybackModeStorageTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "PlaybackModeStorageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToDubbedWhenNothingIsStored() throws {
        let defaults = try makeDefaults()
        #expect(PlaybackMode.stored(profileId: UUID(), in: defaults) == .dubbed)
        #expect(PlaybackMode.stored(profileId: nil, in: defaults) == .dubbed)
    }

    @Test func storesAndRestoresModePerProfile() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        PlaybackMode.subtitled.store(profileId: profile, in: defaults)

        #expect(PlaybackMode.stored(profileId: profile, in: defaults) == .subtitled)
        #expect(defaults.string(forKey: "playbackMode.\(profile.uuidString)") == "subtitled")
    }

    @Test func profilesAreIsolated() throws {
        let defaults = try makeDefaults()
        let first = UUID()
        let second = UUID()
        PlaybackMode.subtitled.store(profileId: first, in: defaults)

        #expect(PlaybackMode.stored(profileId: second, in: defaults) == .dubbed)
        #expect(PlaybackMode.stored(profileId: nil, in: defaults) == .dubbed)
    }

    @Test func nilProfileUsesSharedKey() throws {
        let defaults = try makeDefaults()
        PlaybackMode.subtitled.store(profileId: nil, in: defaults)

        #expect(defaults.string(forKey: "playbackMode") == "subtitled")
        #expect(PlaybackMode.stored(profileId: nil, in: defaults) == .subtitled)
    }

    @Test func unavailableModeFallsBackToDubbed() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        PlaybackMode.enhanced.store(profileId: profile, in: defaults)

        #expect(PlaybackMode.stored(profileId: profile, in: defaults) == .dubbed)
    }

    @Test func unknownRawValueFallsBackToDubbed() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        defaults.set("legacy", forKey: "playbackMode.\(profile.uuidString)")

        #expect(PlaybackMode.stored(profileId: profile, in: defaults) == .dubbed)
    }

    @Test func removeStoredResetsOnlyThatProfile() throws {
        let defaults = try makeDefaults()
        let removed = UUID()
        let kept = UUID()
        PlaybackMode.subtitled.store(profileId: removed, in: defaults)
        PlaybackMode.subtitled.store(profileId: kept, in: defaults)

        PlaybackMode.removeStored(profileId: removed, in: defaults)

        #expect(PlaybackMode.stored(profileId: removed, in: defaults) == .dubbed)
        #expect(PlaybackMode.stored(profileId: kept, in: defaults) == .subtitled)
    }
}
