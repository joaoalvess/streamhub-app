import Foundation
import Testing
@testable import StreamHub

@MainActor
struct PlaybackRoutingTests {

    private func item(
        contentId: String? = "tt0111161",
        kind: MediaItem.Kind,
        service: StreamingService? = nil
    ) -> MediaItem {
        MediaItem(
            contentId: contentId,
            imdbId: contentId?.hasPrefix("tt") == true ? contentId : nil,
            title: "Título",
            kind: kind,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2024,
            streamingSource: service
        )
    }

    @Test func subscribedMovieRoutesToExternalService() {
        let coordinator = PlaybackCoordinator()
        #expect(coordinator.route(for: item(kind: .movie, service: .netflix)) == .externalService(.netflix))
    }

    @Test func subscribedSeriesRoutesToInfuse() {
        let coordinator = PlaybackCoordinator()
        #expect(coordinator.route(for: item(kind: .series, service: .netflix)) == .infuse)
    }

    @Test func unsubscribedMovieRoutesToInfuse() {
        let coordinator = PlaybackCoordinator()
        #expect(coordinator.route(for: item(kind: .movie, service: .hulu)) == .infuse)
    }

    @Test func animeRoutesToInfuse() {
        let coordinator = PlaybackCoordinator()
        #expect(coordinator.route(for: item(contentId: "mal:5114", kind: .anime, service: .crunchyroll)) == .infuse)
    }

    @Test func movieWithoutServiceRoutesToInfuse() {
        let coordinator = PlaybackCoordinator()
        #expect(coordinator.route(for: item(kind: .movie)) == .infuse)
    }

    @Test func playIgnoresPlainSeries() async {
        let coordinator = PlaybackCoordinator()
        await coordinator.play(item: item(contentId: "tt0903747", kind: .series), mode: .dubbed)
        #expect(coordinator.state == .idle)
    }

    @Test func streamRequestUsesAnimeRouteForAnimeCatalogIds() {
        let kitsu = PlaybackCoordinator.streamRequest(videoId: "kitsu:3936:12", isAnime: true)
        #expect(kitsu.type == "anime")
        #expect(kitsu.profile == .anime)

        let mal = PlaybackCoordinator.streamRequest(videoId: "mal:5114:1", isAnime: true)
        #expect(mal.type == "anime")
        #expect(mal.profile == .anime)

        let anilist = PlaybackCoordinator.streamRequest(videoId: "anilist:5114:1", isAnime: true)
        #expect(anilist.type == "anime")
        #expect(anilist.profile == .anime)
    }

    @Test func streamRequestUsesSeriesRouteWithAnimeProfileForAnimeSpecials() {
        let request = PlaybackCoordinator.streamRequest(videoId: "tt1355642:0:1", isAnime: true)
        #expect(request.type == "series")
        #expect(request.profile == .anime)
    }

    @Test func streamRequestLeavesProfileToModeForRegularSeries() {
        let request = PlaybackCoordinator.streamRequest(videoId: "tt0903747:1:1", isAnime: false)
        #expect(request.type == "series")
        #expect(request.profile == nil)
    }

    @Test func runtimeParserMatchesLegacyBehavior() {
        #expect(RuntimeParser.minutes(from: "2h 3min") == 123)
        #expect(RuntimeParser.minutes(from: "2 h 3 min") == 123)
        #expect(RuntimeParser.minutes(from: "1h") == 60)
        #expect(RuntimeParser.minutes(from: "45min") == 45)
        #expect(RuntimeParser.minutes(from: "43") == 43)
        #expect(RuntimeParser.minutes(from: "sem duração") == nil)
        #expect(RuntimeParser.minutes(from: nil) == nil)
    }
}
