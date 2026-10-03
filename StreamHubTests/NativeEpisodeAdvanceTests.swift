import Foundation
import Testing
@testable import StreamHub

@MainActor
@Suite(.serialized)
struct NativeEpisodeAdvanceTests {

    private let base = UUID().uuidString.lowercased()
    private let session = StubURLProtocol.makeSession()
    private let seriesId = "tt9000001"

    private func makeDefaults() throws -> UserDefaults {
        let name = "NativeEpisodeAdvanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeCoordinator(preferences: TrackPreferenceStore? = nil) throws -> PlaybackCoordinator {
        let baseURL = try #require(URL(string: "https://stub.test/\(base)"))
        let api = StreamsAPI(
            session: session,
            gate: RequestGate(limit: 100, window: .seconds(1)),
            baseProvider: { _ in baseURL }
        )
        let defaults = try makeDefaults()
        return PlaybackCoordinator(
            api: api,
            progressStore: PlaybackProgressStore(defaults: defaults),
            trackPreferenceStore: preferences ?? TrackPreferenceStore(defaults: defaults)
        )
    }

    private var series: MediaItem {
        MediaItem(
            contentId: seriesId,
            imdbId: seriesId,
            title: "Série",
            kind: .series,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2020
        )
    }

    private func episode(_ number: Int) -> EpisodeItem {
        EpisodeItem(
            videoId: "\(seriesId):1:\(number)",
            season: 1,
            episode: number,
            title: "Episódio \(number)",
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: 25,
            isReleased: true
        )
    }

    private var timeline: EpisodeTimeline {
        EpisodeTimeline(seasons: [SeasonGroup(number: 1, episodes: [episode(1), episode(2), episode(3)])])
    }

    private func route(_ number: Int) -> String {
        "\(base)/stream/series/\(seriesId):1:\(number).json"
    }

    private func reply(_ number: Int) -> StubReply {
        .json("""
        {"streams":[
            {"name":"B","url":"https://cdn.stub.test/e\(number)-b.mkv","behaviorHints":{"bingeGroup":"group-b"}},
            {"name":"A","url":"https://cdn.stub.test/e\(number)-a.mkv","behaviorHints":{"bingeGroup":"group-a"}}
        ]}
        """)
    }

    private func firstEpisodeReply() -> StubReply {
        .json(#"{"streams":[{"name":"A","url":"https://cdn.stub.test/e1-a.mkv","behaviorHints":{"bingeGroup":"group-a"}}]}"#)
    }

    private func tearDown(_ routes: String...) {
        routes.forEach { StubURLProtocol.routes.remove($0) }
        session.invalidateAndCancel()
    }

    private func startFirstEpisode(_ coordinator: PlaybackCoordinator) async throws -> NativePlaybackSession {
        await coordinator.play(
            item: series,
            episode: episode(1),
            next: episode(2),
            timeline: timeline,
            mode: .subtitled,
            engine: .native
        )
        return try #require(coordinator.nativeSession)
    }

    @Test func advanceUsesPrefetchedStreamFromTheSameBingeGroup() async throws {
        StubURLProtocol.routes.register(route(1), replies: [firstEpisodeReply()])
        StubURLProtocol.routes.register(route(2), replies: [reply(2)])
        defer { tearDown(route(1), route(2)) }
        let coordinator = try makeCoordinator()
        let first = try await startFirstEpisode(coordinator)
        #expect(coordinator.nativeUpNextEpisode?.videoId == episode(2).videoId)

        coordinator.updateNativeDuration(1500)
        coordinator.updateNativePosition(1400)
        await coordinator.advanceToNextEpisode()

        let next = try #require(coordinator.nativeSession)
        #expect(next.id != first.id)
        #expect(next.contentKey == episode(2).videoId)
        #expect(next.videoURL.absoluteString == "https://cdn.stub.test/e2-a.mkv")
        #expect(next.metadata?.episodeNumber == 2)
        #expect(StubURLProtocol.routes.requests(for: route(2)).count == 1)
        #expect(coordinator.progressStore.isWatched(seriesId: seriesId, videoId: episode(1).videoId))
        #expect(coordinator.progressStore.entry(forSeries: seriesId)?.videoId == episode(2).videoId)
        #expect(coordinator.nativeUpNextEpisode?.videoId == episode(3).videoId)
        #expect(coordinator.state == .idle)
    }

    @Test func advanceFetchesAgainWhenPrefetchFailed() async throws {
        StubURLProtocol.routes.register(route(1), replies: [firstEpisodeReply()])
        StubURLProtocol.routes.register(route(2), replies: [.failure(.notConnectedToInternet), reply(2)])
        defer { tearDown(route(1), route(2)) }
        let coordinator = try makeCoordinator()
        _ = try await startFirstEpisode(coordinator)

        coordinator.updateNativeDuration(1500)
        coordinator.updateNativePosition(1400)
        await coordinator.advanceToNextEpisode()

        #expect(StubURLProtocol.routes.requests(for: route(2)).count == 2)
        #expect(coordinator.nativeSession?.contentKey == episode(2).videoId)
        #expect(coordinator.nativeSession?.videoURL.absoluteString == "https://cdn.stub.test/e2-a.mkv")
    }

    @Test func advanceFailureClosesThePlayerWithAnError() async throws {
        StubURLProtocol.routes.register(route(1), replies: [firstEpisodeReply()])
        StubURLProtocol.routes.register(route(2), replies: [.failure(.notConnectedToInternet)])
        defer { tearDown(route(1), route(2)) }
        let coordinator = try makeCoordinator()
        _ = try await startFirstEpisode(coordinator)
        coordinator.updateNativeDuration(1500)
        coordinator.updateNativePosition(600)

        await coordinator.advanceToNextEpisode()

        #expect(coordinator.nativeSession == nil)
        #expect(coordinator.state == .failed(.network))
        #expect(coordinator.nativeUpNextEpisode == nil)
    }

    @Test func lastEpisodeHasNoUpNext() async throws {
        StubURLProtocol.routes.register(route(3), replies: [reply(3)])
        defer { tearDown(route(3)) }
        let coordinator = try makeCoordinator()
        await coordinator.play(item: series, episode: episode(3), next: nil, timeline: timeline, mode: .subtitled, engine: .native)
        let current = try #require(coordinator.nativeSession)

        await coordinator.advanceToNextEpisode()

        #expect(coordinator.nativeUpNextEpisode == nil)
        #expect(coordinator.hasNativeSources)
        #expect(coordinator.nativeSession?.id == current.id)
    }

    @Test func directSessionHasNoEpisodeFeatures() throws {
        defer { tearDown() }
        let coordinator = try makeCoordinator()
        let videoURL = try #require(URL(string: "https://jellyfin.stub.test/video.mkv"))

        coordinator.startNativeSession(videoURL: videoURL, title: "Filme", position: nil, entry: nil)

        #expect(coordinator.nativeUpNextEpisode == nil)
        #expect(!coordinator.hasNativeSources)
    }

    @Test func episodeSessionUsesSeriesPreferencesAndRecordsBothScopes() async throws {
        StubURLProtocol.routes.register(route(1), replies: [firstEpisodeReply()])
        defer { tearDown(route(1)) }
        let preferences = TrackPreferenceStore(defaults: try makeDefaults())
        preferences.record(.audio("ja"), scope: .series(seriesId), profileID: nil)
        preferences.record(.audio("en"), scope: .global, profileID: nil)
        let coordinator = try makeCoordinator(preferences: preferences)
        let current = try await startFirstEpisode(coordinator)
        #expect(current.trackPreferences.audio == "ja")

        coordinator.recordTrackChoice(.subtitlesOff, for: UUID())
        #expect(preferences.preference(for: .global, profileID: nil).subtitlesEnabled)

        coordinator.recordTrackChoice(.subtitlesOff, for: current.id)
        #expect(!preferences.preference(for: .series(seriesId), profileID: nil).subtitlesEnabled)
        #expect(!preferences.preference(for: .global, profileID: nil).subtitlesEnabled)
    }

    @Test func directSessionRecordsOnlyGlobalPreferences() throws {
        defer { tearDown() }
        let preferences = TrackPreferenceStore(defaults: try makeDefaults())
        preferences.record(.audio("ja"), scope: .series(seriesId), profileID: nil)
        preferences.record(.audio("en"), scope: .global, profileID: nil)
        let coordinator = try makeCoordinator(preferences: preferences)
        let videoURL = try #require(URL(string: "https://jellyfin.stub.test/video.mkv"))
        coordinator.startNativeSession(videoURL: videoURL, title: "Filme", position: nil, entry: nil)
        let current = try #require(coordinator.nativeSession)
        #expect(current.trackPreferences.audio == "en")

        coordinator.recordTrackChoice(.audio("pt"), for: current.id)

        #expect(preferences.preference(for: .global, profileID: nil).audio == "pt")
        #expect(preferences.preference(for: .series(seriesId), profileID: nil).audio == "ja")
    }

    @Test func segmentsApplyOnlyToTheMatchingSession() throws {
        defer { tearDown() }
        let coordinator = try makeCoordinator()
        let videoURL = try #require(URL(string: "https://jellyfin.stub.test/video.mkv"))
        coordinator.startNativeSession(videoURL: videoURL, title: "Filme", position: nil, entry: nil)
        let current = try #require(coordinator.nativeSession)
        let segments = [NativeSkipSegment(start: 30, end: 90, kind: .intro)]

        coordinator.setNativeSegments(segments, for: UUID())
        #expect(coordinator.nativeSession?.segments.isEmpty == true)

        coordinator.setNativeSegments(segments, for: current.id)
        #expect(coordinator.nativeSession?.segments == segments)
        #expect(coordinator.nativeSession?.id == current.id)
    }
}
