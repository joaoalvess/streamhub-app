import Foundation
import Testing
@testable import StreamHub

struct LibraryPaginationTests {

    @Test func hasMoreComparesCountToTotal() {
        #expect(LibraryAllViewModel.hasMore(count: 100, total: 250))
        #expect(LibraryAllViewModel.hasMore(count: 250, total: 250) == false)
        #expect(LibraryAllViewModel.hasMore(count: 300, total: 250) == false)
        #expect(LibraryAllViewModel.hasMore(count: 0, total: nil) == false)
    }

    @Test func loadTriggersOnlyNearTheEnd() {
        #expect(LibraryAllViewModel.shouldLoadMore(appearingIndex: 99, count: 100, threshold: 30))
        #expect(LibraryAllViewModel.shouldLoadMore(appearingIndex: 70, count: 100, threshold: 30))
        #expect(LibraryAllViewModel.shouldLoadMore(appearingIndex: 69, count: 100, threshold: 30) == false)
        #expect(LibraryAllViewModel.shouldLoadMore(appearingIndex: 0, count: 100, threshold: 30) == false)
    }
}
