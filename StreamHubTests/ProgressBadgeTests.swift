import Foundation
import Testing
@testable import StreamHub

struct ProgressBadgeTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "ProgressBadgeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func movieEntry(
        contentId: String = "tt0111161",
        runtimeMinutes: Int? = 100,
        position: Int
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

    private func episodeEntry(
        seriesId: String = "tt0903747",
        videoId: String? = "tt0903747:1:1",
        runtimeMinutes: Int? = 50,
        position: Int
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
            videoId: videoId,
            season: 1,
            episode: 1
        )
    }

    private func item(
        contentId: String?,
        imdbId: String?,
        kind: MediaItem.Kind = .movie
    ) -> MediaItem {
        MediaItem(
            contentId: contentId,
            imdbId: imdbId,
            title: "Título",
            kind: kind,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2020
        )
    }

    @Test func movieInProgressReportsProgress() {
        let badge = PlaybackProgressStore.progressBadge(kind: .movie, entry: movieEntry(position: 3_000), movieWatched: false)
        #expect(badge == ProgressBadge.inProgress(0.5))
    }

    @Test func movieProgressHasVisibleFloor() {
        let badge = PlaybackProgressStore.progressBadge(kind: .movie, entry: movieEntry(position: 30), movieWatched: false)
        #expect(badge == ProgressBadge.inProgress(0.03))
    }

    @Test func movieInProgressWinsOverWatched() {
        let badge = PlaybackProgressStore.progressBadge(kind: .movie, entry: movieEntry(position: 3_000), movieWatched: true)
        #expect(badge == ProgressBadge.inProgress(0.5))
    }

    @Test func movieNearCompletionFallsBackToWatchedFlag() {
        let entry = movieEntry(position: 5_700)
        #expect(PlaybackProgressStore.progressBadge(kind: .movie, entry: entry, movieWatched: true) == ProgressBadge.watched)
        #expect(PlaybackProgressStore.progressBadge(kind: .movie, entry: entry, movieWatched: false) == ProgressBadge.none)
    }

    @Test func movieWithoutPositionOrRuntimeIsNotInProgress() {
        #expect(PlaybackProgressStore.progressBadge(kind: .movie, entry: movieEntry(position: 0), movieWatched: false) == ProgressBadge.none)
        #expect(PlaybackProgressStore.progressBadge(kind: .movie, entry: movieEntry(runtimeMinutes: nil, position: 600), movieWatched: false) == ProgressBadge.none)
        #expect(PlaybackProgressStore.progressBadge(kind: .movie, entry: nil, movieWatched: true) == ProgressBadge.watched)
        #expect(PlaybackProgressStore.progressBadge(kind: .movie, entry: nil, movieWatched: false) == ProgressBadge.none)
    }

    @Test func seriesInProgressReportsEpisodeProgress() {
        let badge = PlaybackProgressStore.progressBadge(kind: .series, entry: episodeEntry(position: 1_500), movieWatched: false)
        #expect(badge == ProgressBadge.inProgress(0.5))
        let anime = PlaybackProgressStore.progressBadge(kind: .anime, entry: episodeEntry(runtimeMinutes: nil, position: 600), movieWatched: false)
        #expect(anime == ProgressBadge.inProgress(0.03))
    }

    @Test func seriesWithoutEpisodeOrPositionHasNoBadge() {
        #expect(PlaybackProgressStore.progressBadge(kind: .series, entry: episodeEntry(position: 0), movieWatched: false) == ProgressBadge.none)
        #expect(PlaybackProgressStore.progressBadge(kind: .series, entry: episodeEntry(videoId: nil, position: 600), movieWatched: false) == ProgressBadge.none)
        #expect(PlaybackProgressStore.progressBadge(kind: .series, entry: nil, movieWatched: true) == ProgressBadge.none)
    }

    @MainActor
    @Test func storeResolvesMovieEntryByImdbIdThenContentId() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(movieEntry(contentId: "tt0111161", position: 3_000))
        #expect(store.progressBadge(for: item(contentId: "tmdb:278", imdbId: "tt0111161")) == ProgressBadge.inProgress(0.5))

        store.upsert(movieEntry(contentId: "tmdb:680", position: 1_500))
        #expect(store.progressBadge(for: item(contentId: "tmdb:680", imdbId: "tt0110912")) == ProgressBadge.inProgress(0.25))
    }

    @MainActor
    @Test func storeReportsWatchedMovieAndIgnoresItForSeries() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.markMovieWatched(item(contentId: "tt0111161", imdbId: "tt0111161"))

        #expect(store.progressBadge(for: item(contentId: "tt0111161", imdbId: "tt0111161")) == ProgressBadge.watched)
        #expect(store.progressBadge(for: item(contentId: "tt0111161", imdbId: "tt0111161", kind: .series)) == ProgressBadge.none)
    }

    @MainActor
    @Test func storeReportsSeriesEpisodeInProgress() throws {
        let store = PlaybackProgressStore(defaults: try makeDefaults())
        store.upsert(episodeEntry(position: 1_500))

        #expect(store.progressBadge(for: item(contentId: "tt0903747", imdbId: "tt0903747", kind: .series)) == ProgressBadge.inProgress(0.5))
        #expect(store.progressBadge(for: item(contentId: "tt9999999", imdbId: "tt9999999", kind: .series)) == ProgressBadge.none)
    }
}
