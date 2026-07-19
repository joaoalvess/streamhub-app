import Foundation
import Testing
@testable import StreamHub

struct SearchAPITests {
    @Test func searchPathEncodesSpaces() {
        let path = MetadataAPI.searchPath(type: "movie", id: "search.movie", query: "cidade de deus")
        #expect(path == "catalog/movie/search.movie/search=cidade%20de%20deus.json")
    }

    @Test func searchPathEncodesAccents() {
        let path = MetadataAPI.searchPath(type: "movie", id: "search.movie", query: "ação")
        #expect(path == "catalog/movie/search.movie/search=a%C3%A7%C3%A3o.json")
    }

    @Test func searchPathEncodesReservedCharacters() {
        let path = MetadataAPI.searchPath(type: "series", id: "search.series", query: "naruto & boruto?")
        #expect(path == "catalog/series/search.series/search=naruto%20%26%20boruto%3F.json")
    }

    @Test func searchPathEncodesSlashPlusEquals() {
        let path = MetadataAPI.searchPath(type: "movie", id: "search.movie", query: "AC/DC + a=b")
        #expect(path == "catalog/movie/search.movie/search=AC%2FDC%20%2B%20a%3Db.json")
    }

    @Test func searchPathKeepsTypeAndIdVerbatim() {
        let path = MetadataAPI.searchPath(type: "anime.series", id: "search.anime_series", query: "naruto")
        #expect(path == "catalog/anime.series/search.anime_series/search=naruto.json")
    }

    @Test func searchPathKeepsOuterSpacesVerbatim() {
        let path = MetadataAPI.searchPath(type: "movie", id: "search.movie", query: " batman ")
        #expect(path == "catalog/movie/search.movie/search=%20batman%20.json")
    }
}
