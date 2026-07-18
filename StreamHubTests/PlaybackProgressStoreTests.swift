import Foundation
import Testing
@testable import StreamHub

@MainActor
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
            serviceCode: nil,
            synopsis: nil,
            genres: nil
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

    @Test func setActiveProfileIsolatesEntriesPerProfile() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        let first = UUID()
        let second = UUID()

        store.setActiveProfile(first)
        store.upsert(entry(position: 300))
        #expect(store.entries.count == 1)

        store.setActiveProfile(second)
        #expect(store.entries.isEmpty)

        store.setActiveProfile(first)
        #expect(store.position(for: "tt0111161") == 300)
    }

    @Test func adoptLegacyDataMovesEntriesToFirstProfileOnce() throws {
        let defaults = try makeDefaults()
        let legacy = PlaybackProgressStore(defaults: defaults)
        legacy.upsert(entry(position: 450))

        let store = PlaybackProgressStore(defaults: defaults)
        let profile = UUID()
        store.adoptLegacyDataIfNeeded(for: profile)
        store.setActiveProfile(profile)
        #expect(store.position(for: "tt0111161") == 450)

        store.upsert(entry(position: 900))
        store.adoptLegacyDataIfNeeded(for: profile)
        #expect(store.position(for: "tt0111161") == 900)

        store.setActiveProfile(nil)
        #expect(store.entries.isEmpty)
    }

    private func episodeEntry(
        seriesId: String = "tt0903747",
        metaId: String? = "mal:81",
        videoId: String = "tt0903747:1:1",
        season: Int = 1,
        episode: Int = 1,
        runtimeMinutes: Int? = 45,
        position: Int = 0
    ) -> ResumeEntry {
        ResumeEntry(
            contentId: seriesId,
            imdbId: seriesId,
            title: "Breaking Bad",
            year: 2008,
            posterURL: nil,
            backdropURL: nil,
            logoURL: nil,
            runtimeMinutes: runtimeMinutes,
            positionSeconds: position,
            updatedAt: Date(),
            serviceCode: nil,
            synopsis: nil,
            genres: nil,
            mediaKind: "series",
            metaId: metaId,
            videoId: videoId,
            season: season,
            episode: episode,
            episodeTitle: "Episódio \(episode)"
        )
    }

    private func episodeContext(
        seriesId: String = "tt0903747",
        videoId: String = "tt0903747:1:1",
        season: Int = 1,
        episode: Int = 1,
        next: NextEpisodeRef? = nil
    ) -> EpisodeSessionContext {
        EpisodeSessionContext(
            seriesId: seriesId,
            videoId: videoId,
            season: season,
            episode: episode,
            next: next
        )
    }

    @Test func decodesV1EntriesWithoutEpisodeFields() throws {
        let defaults = try makeDefaults()
        let v1JSON = #"""
        [{
            "contentId": "tt0111161",
            "imdbId": "tt0111161",
            "title": "Um Sonho de Liberdade",
            "year": 1994,
            "runtimeMinutes": 142,
            "positionSeconds": 845,
            "updatedAt": 771000000,
            "serviceCode": "nfx",
            "synopsis": "Dois homens presos criam um laço ao longo dos anos.",
            "genres": ["Drama"]
        }]
        """#
        defaults.set(Data(v1JSON.utf8), forKey: "playback.resume.v1")
        let store = PlaybackProgressStore(defaults: defaults)

        let entry = try #require(store.entries.first)
        #expect(entry.positionSeconds == 845)
        #expect(entry.mediaKind == nil)
        #expect(entry.metaId == nil)
        #expect(entry.videoId == nil)
        #expect(entry.season == nil)
        #expect(entry.episodeCode == nil)
    }

    @Test func episodeCallbackUpdatesPositionWhileIncomplete() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(
            videoURL: "https://cdn/e1.mkv",
            entry: episodeEntry(),
            episodeContext: episodeContext()
        )
        store.applyCallback(lastPlayedURL: "https://cdn/e1.mkv", position: 600)

        let entry = try #require(store.entries.first)
        #expect(entry.positionSeconds == 600)
        #expect(entry.videoId == "tt0903747:1:1")
        #expect(!store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1"))
    }

    @Test func completedEpisodeAdvancesEntryToNext() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        let next = NextEpisodeRef(
            videoId: "tt0903747:1:2",
            season: 1,
            episode: 2,
            title: "Cat's in the Bag...",
            runtimeMinutes: 48
        )
        store.registerSession(
            videoURL: "https://cdn/e1.mkv",
            entry: episodeEntry(),
            episodeContext: episodeContext(next: next)
        )
        store.applyCallback(lastPlayedURL: "https://cdn/e1.mkv", position: 2_700)

        let entry = try #require(store.entries.first)
        #expect(entry.videoId == "tt0903747:1:2")
        #expect(entry.season == 1)
        #expect(entry.episode == 2)
        #expect(entry.episodeTitle == "Cat's in the Bag...")
        #expect(entry.runtimeMinutes == 48)
        #expect(entry.positionSeconds == 0)
        #expect(entry.episodeCode == "T1E2")
        #expect(entry.metaId == "mal:81")
        #expect(store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1"))
    }

    @Test func completedSpecialRestoresPreviousRegularEpisodeEntry() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(episodeEntry(videoId: "tt0903747:2:5", season: 2, episode: 5, position: 600))
        store.registerSession(
            videoURL: "https://cdn/special.mkv",
            entry: episodeEntry(videoId: "tt0903747:0:1", season: 0, episode: 1),
            episodeContext: episodeContext(videoId: "tt0903747:0:1", season: 0, episode: 1)
        )
        store.applyCallback(lastPlayedURL: "https://cdn/special.mkv", position: 2_700)

        let entry = try #require(store.entries.first)
        #expect(entry.videoId == "tt0903747:2:5")
        #expect(entry.positionSeconds == 600)
        #expect(store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:0:1"))
    }

    @Test func completedLastEpisodeRemovesEntryAndMarksWatched() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.registerSession(
            videoURL: "https://cdn/final.mkv",
            entry: episodeEntry(videoId: "tt0903747:5:16", season: 5, episode: 16),
            episodeContext: episodeContext(videoId: "tt0903747:5:16", season: 5, episode: 16)
        )
        store.applyCallback(lastPlayedURL: "https://cdn/final.mkv", position: 2_700)

        #expect(store.entries.isEmpty)
        #expect(store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:5:16"))
    }

    @Test func registerSessionForDifferentEpisodeStartsFromZero() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(episodeEntry(position: 600))
        store.registerSession(
            videoURL: "https://cdn/e2.mkv",
            entry: episodeEntry(videoId: "tt0903747:1:2", episode: 2),
            episodeContext: episodeContext(videoId: "tt0903747:1:2", episode: 2)
        )

        #expect(store.position(for: "tt0903747") == 0)
    }

    @Test func registerSessionForSameEpisodeKeepsPosition() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(episodeEntry(position: 600))
        store.registerSession(
            videoURL: "https://cdn/e1.mkv",
            entry: episodeEntry(),
            episodeContext: episodeContext()
        )

        #expect(store.position(for: "tt0903747") == 600)
    }

    @Test func discardSessionRestoresFullPreviousEpisodeSnapshot() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(episodeEntry(position: 600))
        store.registerSession(
            videoURL: "https://cdn/e2.mkv",
            entry: episodeEntry(videoId: "tt0903747:1:2", episode: 2),
            episodeContext: episodeContext(videoId: "tt0903747:1:2", episode: 2)
        )
        store.discardSession(videoURL: "https://cdn/e2.mkv")

        let entry = try #require(store.entries.first)
        #expect(entry.videoId == "tt0903747:1:1")
        #expect(entry.episode == 1)
        #expect(entry.positionSeconds == 600)
    }

    @Test func watchedCapPrunesOldestSeries() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        for index in 0..<41 {
            store.markWatched(seriesId: "tt\(index)", videoId: "tt\(index):1:1")
        }

        #expect(store.isWatched(seriesId: "tt40", videoId: "tt40:1:1"))
        #expect(!store.isWatched(seriesId: "tt0", videoId: "tt0:1:1"))
        #expect(store.watchedVideoIds(seriesId: "tt1") == ["tt1:1:1"])
    }

    @Test func watchedHistoryIsIsolatedPerProfile() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        let first = UUID()
        let second = UUID()

        store.setActiveProfile(first)
        store.markWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1")
        #expect(store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1"))

        store.setActiveProfile(second)
        #expect(!store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1"))

        store.setActiveProfile(first)
        #expect(store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1"))

        store.removeData(for: first)
        #expect(!store.isWatched(seriesId: "tt0903747", videoId: "tt0903747:1:1"))
    }

    @Test func applyCallbackRoutesToOwningProfile() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        let owner = UUID()
        let other = UUID()

        store.setActiveProfile(owner)
        store.registerSession(videoURL: "https://cdn/a.mkv", entry: entry())

        store.setActiveProfile(other)
        store.applyCallback(lastPlayedURL: "https://cdn/a.mkv", position: 845)
        #expect(store.entries.isEmpty)

        store.setActiveProfile(owner)
        #expect(store.position(for: "tt0111161") == 845)
    }
}
