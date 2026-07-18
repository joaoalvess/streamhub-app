import Foundation
import Testing
@testable import StreamHub

struct MetaModelsTests {

    @Test func decodesSeriesMetaWithSpecialsFirstAndLenientRuntime() throws {
        let json = Data(#"""
        {
          "meta": {
            "id": "tt0903747",
            "type": "series",
            "name": "Breaking Bad",
            "description": "A chemistry teacher turns to a life of crime.",
            "genres": ["Drama", "Crime"],
            "year": "2008",
            "imdbRating": "9.5",
            "runtime": "49min",
            "status": "Ended",
            "poster": "https://example.com/poster.jpg",
            "background": "https://example.com/background.jpg",
            "logo": "https://example.com/logo.png",
            "videos": [
              {
                "id": "tt0903747:0:1",
                "title": "Good Cop / Bad Cop",
                "season": 0,
                "episode": 1,
                "thumbnail": "https://example.com/s0e1.jpg",
                "overview": null,
                "released": null,
                "available": false,
                "runtime": "43min"
              },
              {
                "id": "tt0903747:1:1",
                "title": "Pilot",
                "season": 1,
                "episode": 1,
                "thumbnail": "https://example.com/s1e1.jpg",
                "overview": "Walter White receives a life-changing diagnosis.",
                "released": "2008-01-21T02:00:00.000Z",
                "available": true,
                "runtime": "43min"
              },
              {
                "id": "tt0903747:1:2",
                "title": "Cat's in the Bag...",
                "season": 1,
                "episode": 2,
                "thumbnail": "https://example.com/s1e2.jpg",
                "overview": "Walt and Jesse deal with the aftermath.",
                "released": "2008-01-28T02:00:00.000Z",
                "available": true,
                "runtime": "43min"
              }
            ],
            "behaviorHints": {
              "defaultVideoId": null,
              "hasScheduledVideos": false
            },
            "app_extras": {
              "cast": [
                {
                  "name": "Bryan Cranston",
                  "character": "Walter White",
                  "photo": "https://example.com/cranston.jpg"
                }
              ],
              "directors": [],
              "certificationLocal": "18"
            },
            "_imdbId": "tt0903747"
          }
        }
        """#.utf8)
        let detail = try #require(JSONDecoder().decode(MetaResponse.self, from: json).meta)
        #expect(detail.id == "tt0903747")
        #expect(detail.type == "series")
        #expect(detail.year?.value == "2008")
        #expect(detail.runtime == "49min")
        #expect(detail.status == "Ended")
        #expect(detail.imdbId == "tt0903747")
        #expect(detail.appExtras?.certificationLocal == "18")
        #expect(detail.behaviorHints?.hasScheduledVideos == false)
        let videos = try #require(detail.videos)
        #expect(videos.count == 3)
        let special = try #require(videos.first)
        #expect(special.id == "tt0903747:0:1")
        #expect(special.season == 0)
        #expect(special.available == false)
        #expect(special.runtime?.value == "43min")
    }

    @Test func decodesAnimeMetaWithMixedVideoIds() throws {
        let json = Data(#"""
        {
          "meta": {
            "id": "mal:5114",
            "type": "series",
            "name": "Fullmetal Alchemist: Brotherhood",
            "genres": ["Action", "Adventure", "Anime"],
            "year": 2009,
            "runtime": "24min",
            "status": "Ended",
            "videos": [
              {
                "id": "tt1355642:0:1",
                "title": "The Blind Alchemist",
                "season": 0,
                "episode": 1,
                "released": "2009-08-26T15:00:00.000Z",
                "available": true,
                "runtime": "24min"
              },
              {
                "id": "kitsu:3936:12",
                "title": "One Is All, All Is One",
                "season": 1,
                "episode": 12,
                "released": "2009-06-21T15:00:00.000Z",
                "available": true,
                "runtime": 24
              }
            ],
            "_imdbId": "tt1355642"
          }
        }
        """#.utf8)
        let detail = try #require(JSONDecoder().decode(MetaResponse.self, from: json).meta)
        #expect(detail.id == "mal:5114")
        #expect(detail.year?.value == "2009")
        #expect(detail.imdbId == "tt1355642")
        let videos = try #require(detail.videos)
        #expect(videos.count == 2)
        let special = try #require(videos.first)
        #expect(special.id == "tt1355642:0:1")
        #expect(special.season == 0)
        #expect(special.episode == 1)
        let regular = try #require(videos.last)
        #expect(regular.id == "kitsu:3936:12")
        #expect(regular.season == 1)
        #expect(regular.episode == 12)
        #expect(regular.runtime?.value == "24")
    }

    @Test func decodesNullMetaAsNil() throws {
        let json = Data(#"{"meta": null}"#.utf8)
        let response = try JSONDecoder().decode(MetaResponse.self, from: json)
        #expect(response.meta == nil)
    }

    @Test func metaRequestUsesSeriesTypeForImdbSeries() throws {
        let request = try #require(MetaProvider.metaRequest(for: makeItem(contentId: "tt0903747", kind: .series)))
        #expect(request.type == "series")
        #expect(request.id == "tt0903747")
    }

    @Test func metaRequestKeepsAnimeContentIdVerbatimWithSeriesType() throws {
        let mal = try #require(MetaProvider.metaRequest(for: makeItem(contentId: "mal:5114", kind: .anime)))
        #expect(mal.type == "series")
        #expect(mal.id == "mal:5114")
        let kitsu = try #require(MetaProvider.metaRequest(for: makeItem(contentId: "kitsu:3936", kind: .movie)))
        #expect(kitsu.type == "series")
        #expect(kitsu.id == "kitsu:3936")
    }

    @Test func metaRequestUsesMovieTypeForNonAnimeMovie() throws {
        let request = try #require(MetaProvider.metaRequest(for: makeItem(contentId: "tt1375666", kind: .movie)))
        #expect(request.type == "movie")
        #expect(request.id == "tt1375666")
    }

    @Test func metaRequestFallsBackToImdbIdWhenContentIdMissing() throws {
        let request = try #require(MetaProvider.metaRequest(for: makeItem(imdbId: "tt0903747", kind: .series)))
        #expect(request.type == "series")
        #expect(request.id == "tt0903747")
    }

    @Test func metaRequestReturnsNilWithoutAnyId() {
        #expect(MetaProvider.metaRequest(for: makeItem(kind: .movie)) == nil)
    }

    private func makeItem(contentId: String? = nil, imdbId: String? = nil, kind: MediaItem.Kind) -> MediaItem {
        MediaItem(
            contentId: contentId,
            imdbId: imdbId,
            title: "Title",
            kind: kind,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2024
        )
    }
}
