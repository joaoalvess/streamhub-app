//
//  StreamHubTests.swift
//  StreamHubTests
//
//  Created by João Alves on 19/06/26.
//

import Foundation
import Testing
@testable import StreamHub

struct StreamHubTests {

    @Test func decodesNumericYearFromAnimeCatalog() throws {
        let json = Data(#"{"metas":[{"id":"mal:1","type":"anime","name":"Cowboy Bebop","year":1998}]}"#.utf8)
        let response = try JSONDecoder().decode(CatalogResponse.self, from: json)
        let meta = try #require(response.metas.first)
        #expect(MediaItem(preview: meta).year == 1998)
    }

    @Test func decodesStringYearFromMovieCatalog() throws {
        let json = Data(#"{"metas":[{"id":"tt1","type":"movie","name":"Dune","year":"2024"}]}"#.utf8)
        let response = try JSONDecoder().decode(CatalogResponse.self, from: json)
        let meta = try #require(response.metas.first)
        #expect(MediaItem(preview: meta).year == 2024)
    }

    @Test func animeCatalogMarksItemAsAnimeEvenWhenMetaTypeIsSeries() throws {
        let json = Data(#"{"metas":[{"id":"mal:1","type":"series","name":"Frieren","year":2023}]}"#.utf8)
        let response = try JSONDecoder().decode(CatalogResponse.self, from: json)
        let meta = try #require(response.metas.first)
        #expect(MediaItem(preview: meta, catalogType: "anime").kind == .anime)
    }

}
