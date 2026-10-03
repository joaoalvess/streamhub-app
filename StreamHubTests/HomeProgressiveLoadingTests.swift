import Foundation
import Testing
@testable import StreamHub

struct HomeProgressiveLoadingTests {

    private func item(_ contentId: String) -> MediaItem {
        MediaItem(
            contentId: contentId,
            title: contentId,
            kind: .movie,
            genres: [],
            posterURL: nil,
            backdropURL: URL(string: "https://img/\(contentId).jpg"),
            logoURL: URL(string: "https://img/\(contentId).png"),
            synopsis: "",
            year: 2024
        )
    }

    @Test func fetchOrderStartsWithTheHeroCatalog() {
        #expect(HomeViewModel.fetchOrder(count: 5, heroIndex: 3) == [3, 0, 1, 2, 4])
        #expect(HomeViewModel.fetchOrder(count: 3, heroIndex: 0) == [0, 1, 2])
    }

    @Test func fetchOrderKeepsConfigurationOrderWithoutHero() {
        #expect(HomeViewModel.fetchOrder(count: 4, heroIndex: nil) == [0, 1, 2, 3])
        #expect(HomeViewModel.fetchOrder(count: 2, heroIndex: 7) == [0, 1])
        #expect(HomeViewModel.fetchOrder(count: 0, heroIndex: nil).isEmpty)
    }

    @Test func extendedHeroNeverReordersPublishedItems() {
        let current = [item("tt1"), item("tt2")]
        let extended = HomeViewModel.extendedHero(current, with: [item("tt0"), item("tt2"), item("tt3")])
        #expect(extended.map(\.contentId) == ["tt1", "tt2", "tt0", "tt3"])
        #expect(Array(extended.prefix(2)) == current)
    }

    @Test func extendedHeroStopsAtSevenItems() {
        let current = (1...5).map { item("tt\($0)") }
        let candidates = (1...10).map { item("tt\($0)") }
        let extended = HomeViewModel.extendedHero(current, with: candidates)
        #expect(extended.map(\.contentId) == ["tt1", "tt2", "tt3", "tt4", "tt5", "tt6", "tt7"])
    }

    @Test func extendedHeroStartsFromCandidatesWhenEmpty() {
        let extended = HomeViewModel.extendedHero([], with: [item("tt1"), item("tt1"), item("tt2")])
        #expect(extended.map(\.contentId) == ["tt1", "tt2"])
    }
}
