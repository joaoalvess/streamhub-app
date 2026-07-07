import Foundation
import Testing
@testable import StreamHub

struct StreamProfileTests {

    @Test func dubbedModeMapsToCasualProfile() {
        #expect(StreamProfile(mode: .dubbed) == .casual)
    }

    @Test func subtitledModeMapsToCinemaProfile() {
        #expect(StreamProfile(mode: .subtitled) == .cinema)
    }

    @Test func enhancedModeHasNoProfile() {
        #expect(StreamProfile(mode: .enhanced) == nil)
    }

    @Test func animeKindIsAnime() {
        #expect(item(kind: .anime, contentId: "tt22248376").isAnime)
    }

    @Test func malPrefixedIdIsAnimeEvenWhenKindIsErased() {
        #expect(item(kind: .movie, contentId: "mal:52991").isAnime)
        #expect(item(kind: .series, contentId: "mal:52991").isAnime)
    }

    @Test func kitsuPrefixedIdIsAnime() {
        #expect(item(kind: .movie, contentId: "kitsu:46474").isAnime)
    }

    @Test func crunchyrollSourceIsAnime() {
        #expect(item(kind: .series, contentId: "tt22248376", source: .crunchyroll).isAnime)
    }

    @Test func plainMovieIsNotAnime() {
        #expect(!item(kind: .movie, contentId: "tt0111161").isAnime)
        #expect(!item(kind: .movie, contentId: nil).isAnime)
    }

    private func item(
        kind: MediaItem.Kind,
        contentId: String?,
        source: StreamingService? = nil
    ) -> MediaItem {
        MediaItem(
            contentId: contentId,
            title: "Título",
            kind: kind,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2024,
            streamingSource: source
        )
    }
}
