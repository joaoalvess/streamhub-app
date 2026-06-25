import SwiftUI

enum MenuIcon {
    case symbol(String)
    case asset(String)
}

enum MenuSection: String, Hashable, Identifiable {
    case search, filmes, series, animes
    case netflix, hbo, disney, appleTV, prime, crunchyroll
    case claro, paramount, globoplay, discovery, hulu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "Buscar"
        case .filmes: "Filmes"
        case .series: "Séries"
        case .animes: "Animes"
        case .netflix: "Netflix"
        case .hbo: "HBO Max"
        case .disney: "Disney+"
        case .appleTV: "Apple TV"
        case .prime: "Prime Video"
        case .crunchyroll: "Crunchyroll"
        case .claro: "Claro Video"
        case .paramount: "Paramount+"
        case .globoplay: "Globo Play"
        case .discovery: "Discovery+"
        case .hulu: "Hulu Plus"
        }
    }

    var icon: MenuIcon {
        switch self {
        case .search: .symbol("magnifyingglass")
        case .filmes: .symbol("film")
        case .series: .symbol("tv")
        case .animes: .symbol("sparkles")
        case .netflix: .asset("logo.netflix")
        case .hbo: .asset("logo.hbo")
        case .disney: .asset("logo.disney")
        case .appleTV: .asset("logo.apple")
        case .prime: .asset("logo.prime")
        case .crunchyroll: .asset("logo.crunchyroll")
        case .claro: .asset("logo.claro")
        case .paramount: .asset("logo.paramount")
        case .globoplay: .asset("logo.globoplay")
        case .discovery: .asset("logo.discovery")
        case .hulu: .asset("logo.hulu")
        }
    }

    static let principais: [MenuSection] = [.search, .filmes, .series, .animes]
    static let canais: [MenuSection] = [
        .netflix, .hbo, .disney, .appleTV, .prime, .crunchyroll,
        .claro, .paramount, .globoplay, .discovery, .hulu
    ]
}
