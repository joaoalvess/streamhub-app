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

    @Test func allCatalogTypeFallsBackToPreviewType() throws {
        let json = Data(#"""
        {"metas":[
            {"id":"tt1","type":"series","name":"Série","year":2020},
            {"id":"tt2","type":"movie","name":"Filme","year":2021}
        ]}
        """#.utf8)
        let response = try JSONDecoder().decode(CatalogResponse.self, from: json)
        let series = try #require(response.metas.first)
        let movie = try #require(response.metas.last)
        #expect(MediaItem(preview: series, catalogType: "all").kind == .series)
        #expect(MediaItem(preview: movie, catalogType: "all").kind == .movie)
    }

    private func preview(id: String = "tt10", type: String = "movie") throws -> MetaPreview {
        let json = Data(#"{"metas":[{"id":"\#(id)","type":"\#(type)","name":"Título","year":2024}]}"#.utf8)
        let response = try JSONDecoder().decode(CatalogResponse.self, from: json)
        return try #require(response.metas.first)
    }

    @Test func serviceStampOverridesFlixpatrolCatalog() throws {
        let item = MediaItem(
            preview: try preview(),
            catalogType: "movie",
            catalogId: "flixpatrol.netflix.br.movie",
            service: .netflix
        )
        #expect(item.streamingSource == .netflix)
        #expect(item.serviceBadge == "Netflix")
    }

    @Test func streamingCatalogIdStillDerivesServiceWithoutStamp() throws {
        let item = MediaItem(preview: try preview(), catalogType: "movie", catalogId: "streaming.hbm")
        #expect(item.streamingSource == .hboMax)
    }

    @Test func serviceStampWinsOverCatalogId() throws {
        let item = MediaItem(
            preview: try preview(),
            catalogType: "movie",
            catalogId: "streaming.hbm",
            service: .netflix
        )
        #expect(item.streamingSource == .netflix)
    }

    @Test func crunchyrollStampedSeriesIsAnime() throws {
        let item = MediaItem(
            preview: try preview(id: "tt5", type: "series"),
            catalogType: "series",
            catalogId: "streaming.cru",
            service: .crunchyroll
        )
        #expect(item.kind == .series)
        #expect(item.isAnime)
    }

}
