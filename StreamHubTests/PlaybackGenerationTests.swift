import Foundation
import Testing
@testable import StreamHub

@MainActor
@Suite(.serialized)
struct PlaybackGenerationTests {

    private let base = UUID().uuidString.lowercased()
    private let session = StubURLProtocol.makeSession()

    private func makeDefaults() throws -> UserDefaults {
        let name = "PlaybackGenerationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeCoordinator() throws -> PlaybackCoordinator {
        let baseURL = try #require(URL(string: "https://stub.test/\(base)"))
        let api = StreamsAPI(
            session: session,
            gate: RequestGate(limit: 100, window: .seconds(1)),
            baseProvider: { _ in baseURL }
        )
        return PlaybackCoordinator(api: api, progressStore: PlaybackProgressStore(defaults: try makeDefaults()))
    }

    private func route(_ imdbId: String) -> String {
        "\(base)/stream/movie/\(imdbId).json"
    }

    private func movie(_ imdbId: String) -> MediaItem {
        MediaItem(
            contentId: imdbId,
            imdbId: imdbId,
            title: "Título",
            kind: .movie,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2024,
            streamingSource: nil
        )
    }

    private func playable(_ imdbId: String) -> StubReply {
        .json(#"{"streams":[{"name":"[TB+] 1080p","url":"https://cdn.stub.test/\#(imdbId).mkv"}]}"#)
    }

    private func tearDown(_ routes: String...) {
        routes.forEach { StubURLProtocol.routes.remove($0) }
        session.invalidateAndCancel()
    }

    @Test func currentPlayAppliesItsResult() async throws {
        let id = "tt1000001"
        StubURLProtocol.routes.register(route(id), replies: [playable(id)])
        defer { tearDown(route(id)) }
        let coordinator = try makeCoordinator()

        await coordinator.play(item: movie(id), mode: .subtitled, engine: .native)

        #expect(coordinator.state == .idle)
        #expect(coordinator.nativeSession?.videoURL.absoluteString == "https://cdn.stub.test/\(id).mkv")
    }

    @Test func invalidatedPlayIgnoresItsLateResult() async throws {
        let id = "tt1000002"
        StubURLProtocol.routes.register(route(id), replies: [playable(id)], held: true)
        defer { tearDown(route(id)) }
        let coordinator = try makeCoordinator()
        let item = movie(id)

        let pending = Task { await coordinator.play(item: item, mode: .subtitled, engine: .native) }
        let loading = await pollUntil { coordinator.state == .loading }
        try #require(loading)

        coordinator.invalidatePendingPlay()
        #expect(coordinator.state == .idle)

        StubURLProtocol.routes.release(route(id))
        await pending.value

        #expect(StubURLProtocol.routes.requests(for: route(id)).count == 1)
        #expect(coordinator.state == .idle)
        #expect(coordinator.nativeSession == nil)
    }

    @Test func newerPlayKeepsItsResultWhenAnOlderOneFinishesLate() async throws {
        let older = "tt1000003"
        let newer = "tt1000004"
        StubURLProtocol.routes.register(route(older), replies: [playable(older)], held: true)
        StubURLProtocol.routes.register(route(newer), replies: [.json(#"{"streams":[]}"#)])
        defer { tearDown(route(older), route(newer)) }
        let coordinator = try makeCoordinator()
        let olderItem = movie(older)

        let pending = Task { await coordinator.play(item: olderItem, mode: .subtitled, engine: .native) }
        let loading = await pollUntil { coordinator.state == .loading }
        try #require(loading)
        coordinator.fail(.rateLimited)

        await coordinator.play(item: movie(newer), mode: .subtitled, engine: .native)
        #expect(coordinator.state == .failed(.noSources))

        StubURLProtocol.routes.release(route(older))
        await pending.value

        #expect(StubURLProtocol.routes.requests(for: route(older)).count == 1)
        #expect(coordinator.state == .failed(.noSources))
        #expect(coordinator.nativeSession == nil)
    }

    @Test func invalidatingClearsAFailure() throws {
        defer { tearDown() }
        let coordinator = try makeCoordinator()
        coordinator.fail(.network)

        coordinator.invalidatePendingPlay()

        #expect(coordinator.state == .idle)
    }
}
