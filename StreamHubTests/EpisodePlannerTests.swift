import Foundation
import Testing
@testable import StreamHub

struct EpisodePlannerTests {

    private static let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)

    private func decodeVideos(_ json: String) throws -> [MetaVideo] {
        try JSONDecoder().decode([MetaVideo].self, from: Data(json.utf8))
    }

    private func episode(_ videoId: String, in seasons: [SeasonGroup]) throws -> EpisodeItem {
        try #require(seasons.flatMap(\.episodes).first { $0.videoId == videoId })
    }

    private func seriesSeasons() throws -> [SeasonGroup] {
        let json = """
        [
            {"id": "tt0903747:0:1", "title": "Especial", "season": 0, "episode": 1, "released": "2019-01-01T00:00:00Z"},
            {"id": "tt0903747:1:1", "title": "Piloto", "season": 1, "episode": 1, "released": "2020-01-01T00:00:00Z"},
            {"id": "tt0903747:1:2", "season": 1, "episode": 2, "released": "2020-01-08T00:00:00Z"},
            {"id": "tt0903747:2:1", "season": 2, "episode": 1, "released": "2021-01-01T00:00:00Z"},
            {"id": "tt0903747:2:2", "season": 2, "episode": 2, "released": "2021-01-08T00:00:00Z"},
            {"id": "tt0903747:2:3", "season": 2, "episode": 3, "released": "2999-01-01T00:00:00Z"}
        ]
        """
        return EpisodePlanner.seasons(
            from: try decodeVideos(json),
            fallbackRuntimeMinutes: 40,
            now: Self.fixedNow
        )
    }

    private func resume(
        videoId: String?,
        season: Int? = nil,
        episode: Int? = nil,
        runtimeMinutes: Int? = 40,
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
            runtimeMinutes: runtimeMinutes,
            positionSeconds: position,
            updatedAt: Date(),
            serviceCode: nil,
            synopsis: nil,
            genres: nil,
            mediaKind: "series",
            videoId: videoId,
            season: season,
            episode: episode,
            episodeTitle: nil
        )
    }

    @Test func groupsSeasonsWithSpecialsLastAndEpisodesSorted() throws {
        let json = """
        {
            "meta": {
                "id": "tt0903747",
                "type": "series",
                "name": "Breaking Bad",
                "runtime": "45min",
                "videos": [
                    {"id": "tt0903747:0:2", "season": 0, "episode": 2},
                    {"id": "tt0903747:0:1", "season": 0, "episode": 1},
                    {"id": "tt0903747:2:1", "season": 2, "episode": 1},
                    {"id": "tt0903747:1:2", "season": 1, "episode": 2},
                    {"id": "tt0903747:1:1", "season": 1, "episode": 1},
                    {"id": "tt0903747:2:2", "season": 2, "episode": 2}
                ]
            }
        }
        """
        let response = try JSONDecoder().decode(MetaResponse.self, from: Data(json.utf8))
        let detail = try #require(response.meta)
        let seasons = EpisodePlanner.seasons(
            from: try #require(detail.videos),
            fallbackRuntimeMinutes: RuntimeParser.minutes(from: detail.runtime),
            now: Self.fixedNow
        )

        #expect(seasons.map(\.number) == [1, 2, 0])
        #expect(seasons.map(\.label) == ["Temporada 1", "Temporada 2", "Especiais"])
        #expect(seasons.flatMap(\.episodes).map(\.videoId) == [
            "tt0903747:1:1", "tt0903747:1:2",
            "tt0903747:2:1", "tt0903747:2:2",
            "tt0903747:0:1", "tt0903747:0:2"
        ])
        let first = try episode("tt0903747:1:1", in: seasons)
        #expect(first.title == "Episódio 1")
        #expect(first.runtimeMinutes == 45)
    }

    @Test func preservesMixedAnimeVideoIdsVerbatim() throws {
        let json = """
        [
            {"id": "tt1355642:0:1", "title": "Especial", "season": 0, "episode": 1},
            {"id": "kitsu:3936:12", "title": "Episódio 12", "season": 1, "episode": 12}
        ]
        """
        let seasons = EpisodePlanner.seasons(
            from: try decodeVideos(json),
            fallbackRuntimeMinutes: nil,
            now: Self.fixedNow
        )

        #expect(seasons.map(\.number) == [1, 0])
        let regular = try episode("kitsu:3936:12", in: seasons)
        let special = try episode("tt1355642:0:1", in: seasons)
        #expect(regular.videoId == "kitsu:3936:12")
        #expect(special.videoId == "tt1355642:0:1")
    }

    @Test func derivesIsReleasedFromAvailableAndReleaseDate() throws {
        let json = """
        [
            {"id": "s:1:1", "season": 1, "episode": 1, "available": false, "released": "2020-01-01T00:00:00Z"},
            {"id": "s:1:2", "season": 1, "episode": 2, "released": "2999-01-01T00:00:00.000Z"},
            {"id": "s:1:3", "season": 1, "episode": 3, "released": "2020-01-01T00:00:00Z"},
            {"id": "s:1:4", "season": 1, "episode": 4}
        ]
        """
        let seasons = EpisodePlanner.seasons(
            from: try decodeVideos(json),
            fallbackRuntimeMinutes: nil,
            now: Self.fixedNow
        )

        let episodes = try #require(seasons.first).episodes
        #expect(episodes.map(\.isReleased) == [false, false, true, true])
        #expect(episodes[1].releasedAt != nil)
        #expect(episodes[2].releasedAt != nil)
    }

    @Test func parsesEpisodeRuntimeWithSeriesFallback() throws {
        let json = """
        [
            {"id": "r:1:1", "season": 1, "episode": 1, "runtime": "43min"},
            {"id": "r:1:2", "season": 1, "episode": 2}
        ]
        """
        let videos = try decodeVideos(json)

        let withFallback = EpisodePlanner.seasons(from: videos, fallbackRuntimeMinutes: 45, now: Self.fixedNow)
        #expect(try #require(withFallback.first).episodes.map(\.runtimeMinutes) == [43, 45])

        let withoutFallback = EpisodePlanner.seasons(from: videos, fallbackRuntimeMinutes: nil, now: Self.fixedNow)
        #expect(try #require(withoutFallback.first).episodes.map(\.runtimeMinutes) == [43, nil])
    }

    @Test func nextUnwatchedWithoutHistoryReturnsFirstEpisode() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(seasons: seasons, resume: nil, watched: [])
        #expect(next?.videoId == "tt0903747:1:1")
    }

    @Test func nextUnwatchedResumesPartialEpisode() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: resume(videoId: "tt0903747:1:2", position: 600),
            watched: ["tt0903747:1:1"]
        )
        #expect(next?.videoId == "tt0903747:1:2")
    }

    @Test func nextUnwatchedAdvancesAfterCompletedResume() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: resume(videoId: "tt0903747:1:2", position: 2_300),
            watched: ["tt0903747:1:1", "tt0903747:1:2"]
        )
        #expect(next?.videoId == "tt0903747:2:1")
    }

    @Test func nextUnwatchedCrossesSeasonBoundary() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: nil,
            watched: ["tt0903747:1:1", "tt0903747:1:2"]
        )
        #expect(next?.videoId == "tt0903747:2:1")
    }

    @Test func nextUnwatchedFallsBackToFirstWhenAllWatched() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: resume(videoId: "tt0903747:2:2", position: 2_300),
            watched: ["tt0903747:1:1", "tt0903747:1:2", "tt0903747:2:1", "tt0903747:2:2"]
        )
        #expect(next?.videoId == "tt0903747:1:1")
    }

    @Test func nextUnwatchedMatchesOrphanVideoIdBySeasonEpisode() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: resume(videoId: "legacy:1:2", season: 1, episode: 2, position: 600),
            watched: []
        )
        #expect(next?.videoId == "tt0903747:1:2")
    }

    @Test func nextUnwatchedIgnoresSpecials() throws {
        let seasons = try seriesSeasons()
        let next = EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: nil,
            watched: ["tt0903747:1:1"]
        )
        #expect(next?.videoId == "tt0903747:1:2")
        #expect(next?.season != 0)
    }

    @Test func episodeAfterReturnsNextWithinSeason() throws {
        let seasons = try seriesSeasons()
        let current = try episode("tt0903747:1:1", in: seasons)
        #expect(EpisodePlanner.episodeAfter(current, seasons: seasons)?.videoId == "tt0903747:1:2")
    }

    @Test func episodeAfterCrossesToNextSeason() throws {
        let seasons = try seriesSeasons()
        let current = try episode("tt0903747:1:2", in: seasons)
        #expect(EpisodePlanner.episodeAfter(current, seasons: seasons)?.videoId == "tt0903747:2:1")
    }

    @Test func episodeAfterLastRegularReturnsNilDespiteSpecialsAndUnreleased() throws {
        let seasons = try seriesSeasons()
        let last = try episode("tt0903747:2:2", in: seasons)
        #expect(EpisodePlanner.episodeAfter(last, seasons: seasons) == nil)

        let special = try episode("tt0903747:0:1", in: seasons)
        #expect(EpisodePlanner.episodeAfter(special, seasons: seasons) == nil)

        let unreleased = try episode("tt0903747:2:3", in: seasons)
        #expect(EpisodePlanner.episodeAfter(unreleased, seasons: seasons) == nil)
    }

    @Test func playLabelReflectsResumeState() {
        let next = EpisodeItem(
            videoId: "tt0903747:2:5",
            season: 2,
            episode: 5,
            title: "Confissões",
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: 47,
            isReleased: true
        )

        #expect(EpisodePlanner.playLabel(
            next: next,
            resume: resume(videoId: "tt0903747:2:5", position: 600)
        ) == "Continuar T2E5")
        #expect(EpisodePlanner.playLabel(next: next, resume: nil) == "Reproduzir T2E5")
        #expect(EpisodePlanner.playLabel(next: nil, resume: nil) == "Reproduzir")
    }
}
