import Foundation
import Testing
@testable import StreamHub

@MainActor
struct NativePlaybackSessionTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "NativePlaybackSessionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeCoordinator() throws -> PlaybackCoordinator {
        PlaybackCoordinator(progressStore: PlaybackProgressStore(defaults: try makeDefaults()))
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

    private func videoURL() throws -> URL {
        try #require(URL(string: "https://cdn/a.mkv"))
    }

    @Test func startPublishesSessionAndOptimisticEntry() throws {
        let coordinator = try makeCoordinator()
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Um Sonho de Liberdade", position: 90, entry: entry())

        let session = try #require(coordinator.nativeSession)
        #expect(session.title == "Um Sonho de Liberdade")
        #expect(session.startSeconds == 90)
        #expect(coordinator.state == .idle)
        #expect(coordinator.progressStore.entries.count == 1)
    }

    @Test func startPublishesMetadata() throws {
        let coordinator = try makeCoordinator()
        let metadata = NativeSessionMetadata(
            subtitle: "Piloto",
            synopsis: "Sinopse",
            artworkURL: URL(string: "https://cdn/backdrop.jpg"),
            year: 1994,
            genres: ["Drama"],
            runtimeMinutes: 142,
            ageRatingLabel: "A16",
            ratingLabel: "9.3",
            seasonNumber: 1,
            episodeNumber: 2,
            cast: [
                MediaItem.Person(
                    name: "Tim Robbins",
                    character: "Andy Dufresne",
                    photoURL: URL(string: "https://cdn/tim.jpg")
                ),
            ],
            directors: [
                MediaItem.Person(
                    name: "Frank Darabont",
                    character: nil,
                    photoURL: URL(string: "https://cdn/frank.jpg")
                ),
            ]
        )
        coordinator.startNativeSession(
            videoURL: try videoURL(),
            title: "Lucky",
            position: nil,
            entry: entry(),
            metadata: metadata
        )

        let session = try #require(coordinator.nativeSession)
        #expect(session.title == "Lucky")
        #expect(session.metadata == metadata)
        #expect(session.metadata?.subtitle == "Piloto")
        #expect(session.metadata?.seasonNumber == 1)
        #expect(session.metadata?.episodeNumber == 2)
        #expect(session.metadata?.cast.first?.name == "Tim Robbins")
        #expect(session.metadata?.cast.first?.character == "Andy Dufresne")
        #expect(session.metadata?.directors.first?.name == "Frank Darabont")
    }

    @Test func startWithoutMetadataPublishesNil() throws {
        let coordinator = try makeCoordinator()
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Filme", position: nil, entry: entry())

        let session = try #require(coordinator.nativeSession)
        #expect(session.metadata == nil)
    }

    @Test func completeAppliesLastReportedPosition() throws {
        let coordinator = try makeCoordinator()
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Filme", position: nil, entry: entry())
        coordinator.updateNativePosition(845)
        coordinator.completeNativeSession()

        #expect(coordinator.nativeSession == nil)
        #expect(coordinator.progressStore.position(for: "tt0111161") == 845)
    }

    @Test func completeWithoutTicksDiscardsFreshEntry() throws {
        let coordinator = try makeCoordinator()
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Filme", position: nil, entry: entry())
        coordinator.completeNativeSession()

        #expect(coordinator.nativeSession == nil)
        #expect(coordinator.progressStore.entries.isEmpty)
    }

    @Test func completeTwiceIsNoOp() throws {
        let coordinator = try makeCoordinator()
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Filme", position: nil, entry: entry())
        coordinator.updateNativePosition(845)
        coordinator.completeNativeSession()
        coordinator.completeNativeSession()

        #expect(coordinator.progressStore.position(for: "tt0111161") == 845)
    }

    @Test func finalTickMarksMovieWatched() throws {
        let coordinator = try makeCoordinator()
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Filme", position: nil, entry: entry(runtimeMinutes: 100))
        coordinator.updateNativePosition(5_700)
        coordinator.completeNativeSession()

        #expect(coordinator.progressStore.entries.isEmpty)
    }

    @Test func updateIgnoresZeroAndSessionlessTicks() throws {
        let coordinator = try makeCoordinator()
        coordinator.updateNativePosition(120)
        coordinator.startNativeSession(videoURL: try videoURL(), title: "Filme", position: nil, entry: entry())
        coordinator.updateNativePosition(0)
        coordinator.completeNativeSession()

        #expect(coordinator.progressStore.entries.isEmpty)
    }
}
