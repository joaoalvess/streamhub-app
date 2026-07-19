import Foundation
import Testing
@testable import StreamHub

struct SearchMappingTests {
    private func preview(_ json: String) throws -> MetaPreview {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(MetaPreview.self, from: data)
    }

    @Test func originalPosterIsRewrittenToW500() throws {
        let meta = try preview(
            #"{"id":"tt0317248","type":"movie","name":"Cidade de Deus","poster":"https://image.tmdb.org/t/p/original/x.jpg"}"#
        )
        let item = MediaItem(preview: meta, catalogType: "movie", catalogId: "search.movie")
        #expect(item.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/x.jpg")
    }

    @Test func legacyPosterSizeStillRewritten() throws {
        let meta = try preview(
            #"{"id":"tt1","type":"movie","name":"X","poster":"https://image.tmdb.org/t/p/w600_and_h900_bestv2/x.jpg"}"#
        )
        let item = MediaItem(preview: meta)
        #expect(item.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/x.jpg")
    }

    @Test func nonTMDBPosterPassesThrough() throws {
        let meta = try preview(
            #"{"id":"kitsu:11","type":"series","name":"Naruto","poster":"https://media.kitsu.app/original/poster.jpg"}"#
        )
        let item = MediaItem(preview: meta, catalogType: "anime", catalogId: "search.anime_series")
        #expect(item.posterURL?.absoluteString == "https://media.kitsu.app/original/poster.jpg")
    }

    @Test func backdropKeepsOriginalSize() throws {
        let meta = try preview(
            #"{"id":"tt1","type":"movie","name":"X","background":"https://image.tmdb.org/t/p/original/b.jpg"}"#
        )
        let item = MediaItem(preview: meta)
        #expect(item.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/original/b.jpg")
    }

    @Test func animeSearchPreviewMapsToAnimeKind() throws {
        let meta = try preview(
            #"{"id":"kitsu:11","type":"series","name":"Naruto","_imdbId":null}"#
        )
        let item = MediaItem(preview: meta, catalogType: "anime", catalogId: "search.anime_series")
        #expect(item.kind == .anime)
        #expect(item.isAnime)
        #expect(item.contentId == "kitsu:11")
        #expect(item.imdbId == nil)
    }

    @Test func movieSearchPreviewDerivesImdbIdFromTTId() throws {
        let meta = try preview(
            #"{"id":"tt0317248","type":"movie","name":"Cidade de Deus"}"#
        )
        let item = MediaItem(preview: meta, catalogType: "movie", catalogId: "search.movie")
        #expect(item.imdbId == "tt0317248")
        #expect(item.kind == .movie)
    }
}
