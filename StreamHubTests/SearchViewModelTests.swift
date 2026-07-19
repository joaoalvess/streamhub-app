import Foundation
import Testing
@testable import StreamHub

struct SearchViewModelTests {
    private func item(_ contentId: String, imdbId: String? = nil) -> MediaItem {
        MediaItem(
            contentId: contentId,
            imdbId: imdbId,
            title: contentId,
            kind: .movie,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2020
        )
    }

    @Test func normalizedTrimsWhitespaceAndNewlines() {
        #expect(SearchViewModel.normalized(" cidade de deus \n") == "cidade de deus")
    }

    @Test func aiAutoTriggersOnThreeWordsOrEmptyResults() {
        #expect(SearchViewModel.shouldAutoTriggerAI(query: "filmes como inception", resultsEmpty: false))
        #expect(!SearchViewModel.shouldAutoTriggerAI(query: "batman", resultsEmpty: false))
        #expect(SearchViewModel.shouldAutoTriggerAI(query: "batman", resultsEmpty: true))
        #expect(!SearchViewModel.shouldAutoTriggerAI(query: "harry  potter", resultsEmpty: false))
    }

    @Test func dedupedByIdKeepsFirstOccurrence() throws {
        let data = Data(
            #"{"metas":[{"id":"tt1","type":"movie","name":"A"},{"id":"tt2","type":"movie","name":"B"},{"id":"tt1","type":"movie","name":"C"}]}"#.utf8
        )
        let response = try JSONDecoder().decode(CatalogResponse.self, from: data)
        let deduped = SearchViewModel.dedupedById(response.metas)
        #expect(deduped.map(\.id) == ["tt1", "tt2"])
        #expect(deduped.first?.name == "A")
    }

    @Test func reconciledPreservesItemIdentityAcrossRefinements() {
        let old = [item("tt1"), item("tt2")]
        let incoming = [item("tt2"), item("tt3")]
        let result = SearchViewModel.reconciled(incoming, with: old)
        #expect(result.map(\.contentId) == ["tt2", "tt3"])
        #expect(result[0].id == old[1].id)
        #expect(result[1].id == incoming[1].id)
    }

    @Test func aiSuggestionsDedupeAgainstShownIds() {
        let items = [item("tt1"), item("tt2", imdbId: "tt2"), item("tt3")]
        let result = SearchViewModel.dedupedAgainstShown(items, shownIds: ["tt2"])
        #expect(result.map(\.contentId) == ["tt1", "tt3"])
    }

    @Test func interleavedRoundRobinsDedupesAndCaps() {
        let groups = [
            [item("m1"), item("m2"), item("m3")],
            [item("s1"), item("m1")],
            [item("a1")]
        ]
        let merged = SearchViewModel.interleaved(groups, limit: 5)
        #expect(merged.map(\.contentId) == ["m1", "s1", "a1", "m2", "m3"])
    }
}
