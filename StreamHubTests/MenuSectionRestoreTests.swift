import Foundation
import Testing
@testable import StreamHub

@MainActor
struct MenuSectionRestoreTests {

    @Test func restoresStoredContentSection() {
        #expect(MenuSection.restored(from: "series") == .series)
        #expect(MenuSection.restored(from: "biblioteca") == .biblioteca)
        #expect(MenuSection.restored(from: "netflix") == .netflix)
    }

    @Test func everyContentSectionRoundTrips() {
        for section in MenuSection.principais + MenuSection.canais where section.isRestorable {
            #expect(MenuSection.restored(from: section.rawValue) == section)
        }
    }

    @Test func missingOrInvalidValueFallsBackToFilmes() {
        #expect(MenuSection.restored(from: nil) == .filmes)
        #expect(MenuSection.restored(from: "") == .filmes)
        #expect(MenuSection.restored(from: "Series") == .filmes)
        #expect(MenuSection.restored(from: "removida") == .filmes)
    }

    @Test func searchIsNeverRestored() {
        #expect(!MenuSection.search.isRestorable)
        #expect(MenuSection.restored(from: MenuSection.search.rawValue) == .filmes)
    }
}
