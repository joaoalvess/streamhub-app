import Foundation
import Testing
@testable import StreamHub

@MainActor
struct HomeConfigurationTests {

    private static let channelTable: [MenuSection: (tag: String, service: StreamingService, hero: String)] = [
        .netflix: ("netflix", .netflix, "flixpatrol.netflix.br.movie"),
        .hbo: ("hbo", .hboMax, "flixpatrol.hbo-max.br.movie"),
        .disney: ("disney", .disneyPlus, "flixpatrol.disney.br.movie"),
        .appleTV: ("apple", .appleTVPlus, "flixpatrol.apple-tv.br.movie"),
        .prime: ("prime", .primeVideo, "flixpatrol.amazon-prime.br.movie"),
        .crunchyroll: ("crunchyroll", .crunchyroll, "mal.season_top"),
        .claro: ("claro", .claroVideo, "flixpatrol.apple-tv-store.br.movie"),
        .paramount: ("paramount", .paramountPlus, "flixpatrol.paramount.br.movie"),
        .globoplay: ("globo", .globoplay, "flixpatrol.globoplay.br.movie"),
        .discovery: ("discovery", .discoveryPlus, "flixpatrol.discovery-plus.us.all"),
        .hulu: ("hulu", .hulu, "flixpatrol.hulu.us.movie")
    ]

    @Test func everyChannelHasCompleteConfiguration() throws {
        for section in MenuSection.canais {
            let config = try #require(section.homeConfiguration)
            let expected = try #require(Self.channelTable[section])
            #expect(config.tag == expected.tag)
            #expect(config.service == expected.service)
            #expect(config.heroCatalogId == expected.hero)
            #expect(config.isServiceHome)
            #expect(!config.showsContinueWatching)
        }
    }

    @Test func tagsDoNotDeriveFromRawValue() throws {
        #expect(try #require(MenuSection.appleTV.homeConfiguration).tag == "apple")
        #expect(try #require(MenuSection.globoplay.homeConfiguration).tag == "globo")
    }

    @Test func searchHasNoConfiguration() {
        #expect(MenuSection.search.homeConfiguration == nil)
    }

    @Test func mainPresetsUseCorrectedHeroes() throws {
        #expect(try #require(MenuSection.filmes.homeConfiguration).heroCatalogId == "mdblist.2236")
        #expect(try #require(MenuSection.series.homeConfiguration).heroCatalogId == "trakt.trending.shows")
        #expect(try #require(MenuSection.animes.homeConfiguration).heroCatalogId == "mal.season_top")
        #expect(HomeConfiguration.filmes.tag == "movie")
        #expect(HomeConfiguration.series.tag == "series")
        #expect(HomeConfiguration.animes.tag == "anime")
        #expect(HomeConfiguration.filmes.service == nil)
        #expect(HomeConfiguration.filmes.showsContinueWatching)
        #expect(HomeConfiguration.series.showsContinueWatching)
        #expect(HomeConfiguration.animes.showsContinueWatching)
    }

    private func manifest(_ json: String) throws -> AddonManifest {
        try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8))
    }

    private static let netflixManifestJSON = #"""
    {"catalogs":[
        {"type":"movie","id":"search.movies","name":"Buscar Filmes","extra":[{"name":"search","isRequired":true}]},
        {"type":"series","id":"search.series","name":"Buscar Séries","extra":[{"name":"search","isRequired":true}]},
        {"type":"anime","id":"search.anime","name":"Buscar Animes","extra":[{"name":"search","isRequired":true}]},
        {"type":"movie","id":"gemini.search","name":"Gemini AI Search","extra":[{"name":"search","isRequired":true}]},
        {"type":"series","id":"gemini.search","name":"Gemini AI Search","extra":[{"name":"search","isRequired":true}]},
        {"type":"series","id":"calendar-videos","name":"Calendário","extra":[{"name":"calendarVideosIds","isRequired":true}]},
        {"type":"movie","id":"flixpatrol.netflix.br.movie","name":"Top 10 Netflix Brazil"},
        {"type":"series","id":"flixpatrol.netflix.br.series","name":"Top 10 Netflix Brazil"},
        {"type":"movie","id":"streaming.nfx","name":"Netflix","extra":[{"name":"genre","isRequired":false},{"name":"skip","isRequired":false}]},
        {"type":"series","id":"streaming.nfx","name":"Netflix","extra":[{"name":"genre","isRequired":false},{"name":"skip","isRequired":false}]}
    ]}
    """#

    @Test func serviceHomeKeepsOnlyServiceCatalogsInManifestOrder() throws {
        let config = try #require(MenuSection.netflix.homeConfiguration)
        let included = try manifest(Self.netflixManifestJSON).catalogs.filter { config.includes($0) }
        #expect(included.map(\.id) == [
            "flixpatrol.netflix.br.movie",
            "flixpatrol.netflix.br.series",
            "streaming.nfx",
            "streaming.nfx"
        ])
        #expect(included.map(\.type) == ["movie", "series", "movie", "series"])
    }

    @Test func coreCatalogsAreExcludedEvenWithoutRequiredExtra() throws {
        let config = try #require(MenuSection.netflix.homeConfiguration)
        let relaxedCore = try manifest(#"""
        {"catalogs":[
            {"type":"movie","id":"search.movies","name":"Buscar Filmes","extra":[{"name":"search","isRequired":false}]},
            {"type":"movie","id":"gemini.search","name":"Gemini AI Search"},
            {"type":"series","id":"calendar-videos","name":"Calendário"},
            {"type":"movie","id":"streaming.nfx","name":"Netflix"}
        ]}
        """#)
        #expect(relaxedCore.catalogs.filter { config.includes($0) }.map(\.id) == ["streaming.nfx"])
    }

    @Test func discoveryIncludesAllTypeRanking() throws {
        let config = try #require(MenuSection.discovery.homeConfiguration)
        let catalogs = try manifest(#"""
        {"catalogs":[
            {"type":"movie","id":"search.movies","name":"Buscar","extra":[{"name":"search","isRequired":true}]},
            {"type":"all","id":"flixpatrol.discovery-plus.us.all","name":"Top 10 Discovery+"},
            {"type":"movie","id":"streaming.dpe","name":"Discovery+","extra":[{"name":"skip","isRequired":false}]},
            {"type":"series","id":"streaming.dpe","name":"Discovery+","extra":[{"name":"skip","isRequired":false}]}
        ]}
        """#).catalogs.filter { config.includes($0) }
        #expect(catalogs.map(\.id) == ["flixpatrol.discovery-plus.us.all", "streaming.dpe", "streaming.dpe"])
    }

    @Test func crunchyrollIncludesSeasonTop() throws {
        let config = try #require(MenuSection.crunchyroll.homeConfiguration)
        let catalogs = try manifest(#"""
        {"catalogs":[
            {"type":"anime","id":"mal.season_top","name":"Top da Temporada","extra":[{"name":"skip","isRequired":false}]},
            {"type":"movie","id":"streaming.cru","name":"Crunchyroll","extra":[{"name":"skip","isRequired":false}]},
            {"type":"series","id":"streaming.cru","name":"Crunchyroll","extra":[{"name":"skip","isRequired":false}]}
        ]}
        """#).catalogs.filter { config.includes($0) }
        #expect(catalogs.map(\.id) == ["mal.season_top", "streaming.cru", "streaming.cru"])
    }

    @Test func typeHomeFiltersByTypeOnly() throws {
        let config = HomeConfiguration.filmes
        let catalogs = try manifest(#"""
        {"catalogs":[
            {"type":"movie","id":"mdblist.2236","name":"Em Alta"},
            {"type":"series","id":"trakt.trending.shows","name":"Séries em Alta"},
            {"type":"movie","id":"search.movies","name":"Buscar","extra":[{"name":"search","isRequired":true}]}
        ]}
        """#).catalogs.filter { config.includes($0) }
        #expect(catalogs.map(\.id) == ["mdblist.2236"])
    }

    @Test func rowTitlesForServiceHomes() {
        let netflix = HomeConfiguration.channel(
            tag: "netflix", service: .netflix, heroCatalogId: "flixpatrol.netflix.br.movie"
        )
        #expect(netflix.rowTitle(for: def(type: "movie", id: "flixpatrol.netflix.br.movie")) == "Top 10: Filmes")
        #expect(netflix.rowTitle(for: def(type: "series", id: "flixpatrol.netflix.br.series")) == "Top 10: Séries")
        #expect(netflix.rowTitle(for: def(type: "all", id: "flixpatrol.discovery-plus.us.all")) == "Top 10")
        #expect(netflix.rowTitle(for: def(type: "movie", id: "streaming.nfx")) == "Filmes")
        #expect(netflix.rowTitle(for: def(type: "series", id: "streaming.nfx")) == "Séries")
        #expect(netflix.rowTitle(for: def(type: "anime", id: "mal.season_top")) == "Top da temporada")
    }

    @Test func typeHomeKeepsCatalogName() {
        let definition = def(type: "movie", id: "mdblist.2236", name: "Em Alta")
        #expect(HomeConfiguration.filmes.rowTitle(for: definition) == "Em Alta")
    }

    @Test func flixpatrolStyleIsTop10RegardlessOfName() {
        #expect(HomeViewModel.style(for: def(type: "movie", id: "flixpatrol.netflix.br.movie", name: "Top 10: Filmes")) == .top10)
        #expect(HomeViewModel.style(for: def(type: "movie", id: "flixpatrol.netflix.br.movie", name: "Qualquer Nome")) == .top10)
        #expect(HomeViewModel.style(for: def(type: "anime", id: "mal.season_top", name: "Top da temporada")) == .standard)
        #expect(HomeViewModel.style(for: def(type: "movie", id: "mdblist.2236", name: "Top 10 da Semana")) == .top10)
        #expect(HomeViewModel.style(for: def(type: "movie", id: "streaming.nfx", name: "Filmes")) == .standard)
    }

    private func def(type: String, id: String, name: String = "Catálogo") -> CatalogDefinition {
        CatalogDefinition(type: type, id: id, name: name, extra: nil)
    }

    private func previews(_ json: String) throws -> [MetaPreview] {
        try JSONDecoder().decode(CatalogResponse.self, from: Data(json.utf8)).metas
    }

    @Test func heroPoolTopsUpToSevenWithoutDuplicates() throws {
        let heroMetas = try previews(#"""
        {"metas":[
            {"id":"tt1","type":"movie","name":"A","background":"https://img/a.jpg","logo":"https://img/a.png"},
            {"id":"tt2","type":"movie","name":"B","background":"https://img/b.jpg","logo":"https://img/b.png"},
            {"id":"tt3","type":"movie","name":"C","background":"https://img/c.jpg"}
        ]}
        """#)
        let fillMetas = try previews(#"""
        {"metas":[
            {"id":"tt2","type":"movie","name":"B","background":"https://img/b.jpg","logo":"https://img/b.png"},
            {"id":"tt4","type":"movie","name":"D","background":"https://img/d.jpg","logo":"https://img/d.png"},
            {"id":"tt5","type":"movie","name":"E","background":"https://img/e.jpg","logo":"https://img/e.png"},
            {"id":"tt6","type":"movie","name":"F","background":"https://img/f.jpg","logo":"https://img/f.png"},
            {"id":"tt7","type":"series","name":"G","background":"https://img/g.jpg","logo":"https://img/g.png"},
            {"id":"tt8","type":"movie","name":"H","background":"https://img/h.jpg","logo":"https://img/h.png"},
            {"id":"tt9","type":"movie","name":"I","background":"https://img/i.jpg","logo":"https://img/i.png"}
        ]}
        """#)
        let config = HomeConfiguration.channel(
            tag: "netflix", service: .netflix, heroCatalogId: "flixpatrol.netflix.br.movie"
        )
        let pool = HomeViewModel.heroPool(
            pages: [
                (def: def(type: "series", id: "streaming.nfx"), metas: fillMetas),
                (def: def(type: "movie", id: "flixpatrol.netflix.br.movie"), metas: heroMetas)
            ],
            config: config
        )
        #expect(pool.count == 7)
        #expect(pool.map(\.contentId) == ["tt1", "tt2", "tt4", "tt5", "tt6", "tt7", "tt8"])
        #expect(pool.allSatisfy { $0.backdropURL != nil && $0.logoURL != nil })
        #expect(pool.allSatisfy { $0.streamingSource == .netflix })
    }

    @Test func heroPoolWithoutServiceKeepsCatalogDerivedSource() throws {
        let metas = try previews(#"""
        {"metas":[
            {"id":"tt1","type":"movie","name":"A","background":"https://img/a.jpg","logo":"https://img/a.png"}
        ]}
        """#)
        let pool = HomeViewModel.heroPool(
            pages: [(def: def(type: "movie", id: "mdblist.2236"), metas: metas)],
            config: .filmes
        )
        #expect(pool.count == 1)
        #expect(pool.first?.streamingSource == nil)
        #expect(pool.first?.kind == .movie)
    }
}
