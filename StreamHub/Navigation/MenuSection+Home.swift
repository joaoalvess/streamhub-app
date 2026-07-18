import Foundation

nonisolated extension MenuSection {
    var homeConfiguration: HomeConfiguration? {
        switch self {
        case .search:
            nil
        case .filmes:
            .filmes
        case .series:
            .series
        case .animes:
            .animes
        case .netflix:
            .channel(tag: "netflix", service: .netflix, heroCatalogId: "flixpatrol.netflix.br.movie")
        case .hbo:
            .channel(tag: "hbo", service: .hboMax, heroCatalogId: "flixpatrol.hbo-max.br.movie")
        case .disney:
            .channel(tag: "disney", service: .disneyPlus, heroCatalogId: "flixpatrol.disney.br.movie")
        case .appleTV:
            .channel(tag: "apple", service: .appleTVPlus, heroCatalogId: "flixpatrol.apple-tv.br.movie")
        case .prime:
            .channel(tag: "prime", service: .primeVideo, heroCatalogId: "flixpatrol.amazon-prime.br.movie")
        case .crunchyroll:
            .channel(tag: "crunchyroll", service: .crunchyroll, heroCatalogId: "mal.season_top")
        case .claro:
            .channel(tag: "claro", service: .claroVideo, heroCatalogId: "flixpatrol.apple-tv-store.br.movie")
        case .paramount:
            .channel(tag: "paramount", service: .paramountPlus, heroCatalogId: "flixpatrol.paramount.br.movie")
        case .globoplay:
            .channel(tag: "globo", service: .globoplay, heroCatalogId: "flixpatrol.globoplay.br.movie")
        case .discovery:
            .channel(tag: "discovery", service: .discoveryPlus, heroCatalogId: "flixpatrol.discovery-plus.us.all")
        case .hulu:
            .channel(tag: "hulu", service: .hulu, heroCatalogId: "flixpatrol.hulu.us.movie")
        }
    }
}
