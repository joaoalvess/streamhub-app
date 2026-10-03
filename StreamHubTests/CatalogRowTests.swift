import Foundation
import Testing
@testable import StreamHub

@MainActor
@Suite(.serialized)
struct CatalogRowTests {

    private let catalogId = UUID().uuidString.lowercased()
    private let session = StubURLProtocol.makeSession()

    private func metasJSON(_ ids: [String]) -> String {
        let metas = ids.map { id in #"{"id":"\#(id)","type":"movie","name":"Filme \#(id)"}"# }
        return #"{"metas":["# + metas.joined(separator: ",") + "]}"
    }

    private func makeRow() throws -> CatalogRow {
        let firstPage = try JSONDecoder().decode(
            CatalogResponse.self,
            from: Data(metasJSON(["tt1", "tt2", "tt3", "tt4", "tt5"]).utf8)
        ).metas
        return CatalogRow(
            api: MetadataAPI(session: session),
            type: "movie",
            id: catalogId,
            title: "Populares",
            style: .standard,
            firstPage: firstPage
        )
    }

    private var requestedPages: [String] {
        StubURLProtocol.routes.requests(for: catalogId).map(\.lastPathComponent)
    }

    private func tearDown() {
        StubURLProtocol.routes.remove(catalogId)
        session.invalidateAndCancel()
    }

    @Test func failedPageDoesNotEndTheRowAndIsRetried() async throws {
        StubURLProtocol.routes.register(catalogId, replies: [
            .status(500, Data()),
            .json(metasJSON(["tt6", "tt7", "tt8"])),
            .status(500, Data())
        ])
        defer { tearDown() }
        let row = try makeRow()
        #expect(row.displayCount == 5)

        row.onCardAppear(4)
        let failed = await pollUntil { requestedPages.count == 1 }
        try #require(failed)

        let retried = await pollUntil {
            if requestedPages.count >= 2 { return true }
            row.onCardAppear(4)
            return false
        }
        try #require(retried)

        let grown = await pollUntil { row.displayCount == 8 && requestedPages.count == 3 }
        try #require(grown)

        #expect(requestedPages == ["skip=5.json", "skip=5.json", "skip=8.json"])
        #expect(row.item(at: 5).contentId == "tt6")
        #expect(row.item(at: 7).contentId == "tt8")
    }

    @Test func emptyPageEndsTheRowAndLoopsItsItems() async throws {
        StubURLProtocol.routes.register(catalogId, replies: [.json(metasJSON([]))])
        defer { tearDown() }
        let row = try makeRow()

        row.onCardAppear(4)
        let looped = await pollUntil { row.displayCount == 10 }
        try #require(looped)

        row.onCardAppear(9)

        #expect(row.displayCount == 15)
        #expect(row.item(at: 7).contentId == "tt3")
        try await Task.sleep(for: .milliseconds(100))
        #expect(requestedPages == ["skip=5.json"])
    }
}
