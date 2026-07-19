import Lumen
import XCTest

final class TVPlayerMetadataTests: XCTestCase {
    func testEpisodeContextIncludesSeasonEpisodeAndTitle() {
        let metadata = TVPlayerMetadata(
            subtitle: "Sem atalhos",
            seasonNumber: 1,
            episodeNumber: 1,
            year: 2026
        )

        XCTAssertEqual(metadata.contextLabel, "T1, E1 · Sem atalhos")
    }

    func testEpisodeContextOmitsMissingTitle() {
        let metadata = TVPlayerMetadata(
            subtitle: "   ",
            seasonNumber: 2,
            episodeNumber: 4
        )

        XCTAssertEqual(metadata.contextLabel, "T2, E4")
    }

    func testMovieContextUsesYear() {
        let metadata = TVPlayerMetadata(subtitle: "Ignored for movies", year: 2026)

        XCTAssertEqual(metadata.contextLabel, "2026")
    }

    func testIncompleteContextFallsBackToSubtitle() {
        let metadata = TVPlayerMetadata(subtitle: "Especial")

        XCTAssertEqual(metadata.contextLabel, "Especial")
    }

    func testEmptyMetadataHasNoContext() {
        XCTAssertNil(TVPlayerMetadata().contextLabel)
    }
}
