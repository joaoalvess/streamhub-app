import Foundation
import Testing
@testable import StreamHub

struct PlayPlannerTests {

    private enum Outcome: Equatable {
        case movie
        case episode(EpisodeItem, next: EpisodeItem?)
        case blocked(PlaybackCoordinator.PlaybackError)
        case pending
    }

    private func outcome(_ resolution: PlayResolution) -> Outcome {
        switch resolution {
        case .target(.movie): .movie
        case .target(.episode(let episode, let next)): .episode(episode, next: next)
        case .blocked(let error): .blocked(error)
        case .pending: .pending
        }
    }

    private func item(
        contentId: String? = "tt0903747",
        imdbId: String? = "tt0903747",
        kind: MediaItem.Kind = .series,
        runtime: String? = nil
    ) -> MediaItem {
        MediaItem(
            contentId: contentId,
            imdbId: imdbId,
            title: "Breaking Bad",
            kind: kind,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2008,
            runtime: runtime
        )
    }

    private func movie() -> MediaItem {
        item(contentId: "tt0111161", imdbId: "tt0111161", kind: .movie)
    }

    private func anime() -> MediaItem {
        item(contentId: "kitsu:3936", imdbId: nil, kind: .anime)
    }

    private func episode(_ videoId: String, season: Int = 1, number: Int = 1) -> EpisodeItem {
        EpisodeItem(
            videoId: videoId,
            season: season,
            episode: number,
            title: "Episódio \(number)",
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: 47,
            isReleased: true
        )
    }

    private func defaultEpisode(_ videoId: String, runtimeMinutes: Int?) -> EpisodeItem {
        EpisodeItem(
            videoId: videoId,
            season: 1,
            episode: 1,
            title: "Breaking Bad",
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: runtimeMinutes,
            isReleased: true
        )
    }

    private func resume(
        videoId: String?,
        season: Int? = nil,
        episode: Int? = nil,
        episodeTitle: String? = nil,
        position: Int = 0
    ) -> ResumeEntry {
        ResumeEntry(
            contentId: "tt0903747",
            imdbId: "tt0903747",
            title: "Breaking Bad",
            year: 2008,
            posterURL: nil,
            backdropURL: nil,
            logoURL: nil,
            runtimeMinutes: 47,
            positionSeconds: position,
            updatedAt: Date(),
            serviceCode: nil,
            synopsis: nil,
            genres: nil,
            mediaKind: "series",
            videoId: videoId,
            season: season,
            episode: episode,
            episodeTitle: episodeTitle
        )
    }

    @Test func seriesAndAnimeAreSeriesLike() {
        #expect(PlayPlanner.isSeriesLike(item()))
        #expect(PlayPlanner.isSeriesLike(anime()))
        #expect(PlayPlanner.isSeriesLike(item(contentId: "mal:5114", imdbId: nil, kind: .movie)))
        #expect(!PlayPlanner.isSeriesLike(movie()))
    }

    @Test func seriesIdPrefersImdbThenContentId() {
        #expect(PlayPlanner.seriesId(for: item(contentId: "tmdb:1396", imdbId: "tt0903747")) == "tt0903747")
        #expect(PlayPlanner.seriesId(for: item(contentId: "kitsu:3936", imdbId: nil)) == "kitsu:3936")
        #expect(PlayPlanner.seriesId(for: item(contentId: nil, imdbId: nil)).isEmpty)
    }

    @Test func resumeEpisodeRebuildsTheStoredEpisode() throws {
        let entry = resume(videoId: "tt0903747:2:3", season: 2, episode: 3, episodeTitle: "Bit by a Dead Bee")
        let episode = try #require(PlayPlanner.resumeEpisode(from: entry, item: item()))

        #expect(episode.videoId == "tt0903747:2:3")
        #expect(episode.season == 2)
        #expect(episode.episode == 3)
        #expect(episode.title == "Bit by a Dead Bee")
        #expect(episode.runtimeMinutes == 47)
        #expect(episode.isReleased)
    }

    @Test func resumeEpisodeDefaultsToFirstEpisodeAndSeriesTitle() throws {
        let episode = try #require(PlayPlanner.resumeEpisode(from: resume(videoId: "tt0903747:1:1"), item: item()))

        #expect(episode.season == 1)
        #expect(episode.episode == 1)
        #expect(episode.title == "Breaking Bad")
    }

    @Test func resumeEpisodeNeedsAVideoId() {
        #expect(PlayPlanner.resumeEpisode(from: nil, item: item()) == nil)
        #expect(PlayPlanner.resumeEpisode(from: resume(videoId: nil, season: 1, episode: 2), item: item()) == nil)
    }

    @Test func resumeLabelContinuesOnlyWithProgress() {
        #expect(PlayPlanner.resumeLabel(for: resume(videoId: "tt0903747:2:3", season: 2, episode: 3, position: 120)) == "Continuar T2E3")
        #expect(PlayPlanner.resumeLabel(for: resume(videoId: "tt0903747:2:3", season: 2, episode: 3)) == "Reproduzir T2E3")
    }

    @Test func resumeLabelFallsBackWithoutAnEpisodeReference() {
        #expect(PlayPlanner.resumeLabel(for: nil) == "Reproduzir")
        #expect(PlayPlanner.resumeLabel(for: resume(videoId: nil, season: 2, episode: 3, position: 120)) == "Reproduzir")
        #expect(PlayPlanner.resumeLabel(for: resume(videoId: "tt0903747:2:3", position: 120)) == "Reproduzir")
    }

    @Test func moviesPlayAsMovies() {
        #expect(PlayPlanner.isPlayEnabled(for: movie(), in: .movie))
        #expect(outcome(PlayPlanner.resolveTarget(for: movie(), in: .movie)) == .movie)
    }

    @Test func loadedSeriesPlaysTheNextEpisodeWithTheOneAfterIt() {
        let next = episode("tt0903747:2:1", season: 2, number: 1)
        let after = episode("tt0903747:2:2", season: 2, number: 2)
        let context = PlayPlanner.Context.loaded(next: next, nextAfter: after, defaultVideoId: nil)

        #expect(PlayPlanner.isPlayEnabled(for: item(), in: context))
        #expect(outcome(PlayPlanner.resolveTarget(for: item(), in: context)) == .episode(next, next: after))
    }

    @Test func loadedSeriesWithoutNextFallsBackToTheDefaultVideo() {
        let series = item(runtime: "47min")
        let context = PlayPlanner.Context.loaded(next: nil, nextAfter: nil, defaultVideoId: "tt0903747:1:1")

        #expect(PlayPlanner.isPlayEnabled(for: series, in: context))
        #expect(outcome(PlayPlanner.resolveTarget(for: series, in: context)) == .episode(
            defaultEpisode("tt0903747:1:1", runtimeMinutes: 47),
            next: nil
        ))
    }

    @Test func loadedWithoutNextOrUsableDefaultIsBlocked() {
        let noDefault = PlayPlanner.Context.loaded(next: nil, nextAfter: nil, defaultVideoId: nil)
        #expect(!PlayPlanner.isPlayEnabled(for: item(), in: noDefault))
        #expect(outcome(PlayPlanner.resolveTarget(for: item(), in: noDefault)) == .blocked(.noEpisodes))

        let animeDefault = PlayPlanner.Context.loaded(next: nil, nextAfter: nil, defaultVideoId: "kitsu:3936:1")
        #expect(!PlayPlanner.isPlayEnabled(for: anime(), in: animeDefault))
        #expect(outcome(PlayPlanner.resolveTarget(for: anime(), in: animeDefault)) == .blocked(.noEpisodes))
    }

    @Test func unavailableSeriesUsesTheDefaultVideo() {
        let context = PlayPlanner.Context.unavailable(defaultVideoId: "tt0903747:1:1")

        #expect(PlayPlanner.isPlayEnabled(for: item(), in: context))
        #expect(outcome(PlayPlanner.resolveTarget(for: item(), in: context)) == .episode(
            defaultEpisode("tt0903747:1:1", runtimeMinutes: nil),
            next: nil
        ))
    }

    @Test func unavailableSeriesWithoutDefaultStaysEnabledButIsBlocked() {
        let context = PlayPlanner.Context.unavailable(defaultVideoId: nil)

        #expect(PlayPlanner.isPlayEnabled(for: item(), in: context))
        #expect(outcome(PlayPlanner.resolveTarget(for: item(), in: context)) == .blocked(.noEpisodes))
    }

    @Test func unavailableAnimePlaysAsMovie() {
        let context = PlayPlanner.Context.unavailable(defaultVideoId: "kitsu:3936:1")

        #expect(PlayPlanner.isPlayEnabled(for: anime(), in: context))
        #expect(outcome(PlayPlanner.resolveTarget(for: anime(), in: context)) == .movie)
    }

    @Test func pendingSeriesResumesTheStoredEpisodeWithoutNext() throws {
        let entry = resume(videoId: "tt0903747:2:3", season: 2, episode: 3)
        let expected = try #require(PlayPlanner.resumeEpisode(from: entry, item: item()))
        let context = PlayPlanner.Context.pending(resume: entry)

        #expect(PlayPlanner.isPlayEnabled(for: item(), in: context))
        #expect(outcome(PlayPlanner.resolveTarget(for: item(), in: context)) == .episode(expected, next: nil))
    }

    @Test func pendingSeriesWithoutResumableEntryWaits() {
        let entries: [ResumeEntry?] = [nil, resume(videoId: nil, season: 1, episode: 2)]
        for entry in entries {
            let context = PlayPlanner.Context.pending(resume: entry)
            #expect(!PlayPlanner.isPlayEnabled(for: item(), in: context))
            #expect(outcome(PlayPlanner.resolveTarget(for: item(), in: context)) == .pending)
        }
    }

    @Test func contentKeyUsesContentIdForMoviesAndVideoIdForEpisodes() {
        let target = episode("tt0903747:1:2", number: 2)

        #expect(PlayPlanner.contentKey(for: .movie, item: movie()) == "tt0111161")
        #expect(PlayPlanner.contentKey(for: .episode(target, next: nil), item: item()) == "tt0903747:1:2")
    }
}
