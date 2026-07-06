import Foundation
import Testing
@testable import StreamHub

struct PlaybackProgressStoreTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "PlaybackProgressStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func entry(
        contentId: String = "tt0111161",
        runtimeMinutes: Int? = 142,
        position: Int = 0
    ) -> ResumeEntry {
        ResumeEntry(
            contentId: contentId,
            imdbId: contentId,
            title: "Um Sonho de Liberdade",
            year: 1994,
            posterURL: nil,
            backdropURL: nil,
            logoURL: nil,
            runtimeMinutes: runtimeMinutes,
            positionSeconds: position,
            updatedAt: Date(),
            serviceCode: nil
        )
    }

    @Test func registerSessionCreatesOptimisticEntry() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())

        #expect(store.entries.count == 1)
        #expect(store.position(for: "tt0111161") == 0)
    }

    @Test func applyCallbackUpdatesPosition() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())
        store.applyCallback(lastPlayedURL: "https://cdn/a.mkv", position: 845)

        #expect(store.position(for: "tt0111161") == 845)
    }

    @Test func applyCallbackRemovesCompletedMovie() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry(runtimeMinutes: 100))
        store.applyCallback(lastPlayedURL: "https://cdn/a.mkv", position: 5_700)

        #expect(store.entries.isEmpty)
    }

    @Test func applyCallbackIgnoresUnknownURL() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())
        store.applyCallback(lastPlayedURL: "https://cdn/other.mkv", position: 500)

        #expect(store.position(for: "tt0111161") == 0)
    }

    @Test func discardSessionRemovesFreshEntry() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())
        store.discardSession(videoURL: "https://cdn/a.mkv")

        #expect(store.entries.isEmpty)
    }

    @Test func discardSessionRestoresPreviousPosition() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(entry(position: 600))
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())
        store.discardSession(videoURL: "https://cdn/a.mkv")

        #expect(store.position(for: "tt0111161") == 600)
    }

    @Test func persistsAcrossInstances() throws {
        let defaults = try makeDefaults()
        let first = PlaybackProgressStore(defaults: defaults)
        first.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())
        first.applyCallback(lastPlayedURL: "https://cdn/a.mkv", position: 845)

        let second = PlaybackProgressStore(defaults: defaults)
        #expect(second.position(for: "tt0111161") == 845)
    }

    @Test func sessionSurvivesRestartBeforeCallback() throws {
        let defaults = try makeDefaults()
        let first = PlaybackProgressStore(defaults: defaults)
        first.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())

        let second = PlaybackProgressStore(defaults: defaults)
        second.applyCallback(lastPlayedURL: "https://cdn/a.mkv", position: 845)
        #expect(second.position(for: "tt0111161") == 845)
    }

    @Test func capsEntriesAtTwenty() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        for index in 0..<25 {
            store.upsert(entry(contentId: "tt\(index)"))
        }
        #expect(store.entries.count == 20)
        #expect(store.position(for: "tt24") != nil)
        #expect(store.position(for: "tt0") == nil)
    }

    @Test func progressAndRemainingLabelDeriveFromRuntime() {
        let resumed = entry(runtimeMinutes: 100, position: 3_000)
        #expect(resumed.progress == 0.5)
        #expect(resumed.remainingLabel == "Restam 50 min")

        let unknownRuntime = entry(runtimeMinutes: nil, position: 3_000)
        #expect(unknownRuntime.progress == nil)
    }
}
