import Foundation

nonisolated struct HomeConfiguration: Hashable, Sendable {
    let tag: String
    let heroCatalogId: String
    let service: StreamingService?
    let showsContinueWatching: Bool

    var isServiceHome: Bool { service != nil }

    func includes(_ def: CatalogDefinition) -> Bool {
        guard !def.hasRequiredExtra else { return false }
        if isServiceHome {
            return !Self.isCoreCatalog(def)
        }
        return def.type == tag
    }

    func rowTitle(for def: CatalogDefinition) -> String {
        guard isServiceHome else { return def.name }
        if def.id.hasPrefix("flixpatrol.") {
            switch def.type {
            case "movie": return "Top 10: Filmes"
            case "series": return "Top 10: Séries"
            default: return "Top 10"
            }
        }
        if def.id.hasPrefix("streaming.") {
            switch def.type {
            case "movie": return "Filmes"
            case "series": return "Séries"
            default: return def.name
            }
        }
        if def.id == "mal.season_top" { return "Top da temporada" }
        return def.name
    }

    private static func isCoreCatalog(_ def: CatalogDefinition) -> Bool {
        def.id.hasPrefix("search.") || def.id.hasPrefix("gemini.") || def.id == "calendar-videos"
    }

    static func channel(
        tag: String,
        service: StreamingService,
        heroCatalogId: String
    ) -> HomeConfiguration {
        HomeConfiguration(
            tag: tag,
            heroCatalogId: heroCatalogId,
            service: service,
            showsContinueWatching: false
        )
    }

    static let filmes = HomeConfiguration(
        tag: "movie",
        heroCatalogId: "mdblist.2236",
        service: nil,
        showsContinueWatching: true
    )

    static let series = HomeConfiguration(
        tag: "series",
        heroCatalogId: "trakt.trending.shows",
        service: nil,
        showsContinueWatching: true
    )

    static let animes = HomeConfiguration(
        tag: "anime",
        heroCatalogId: "mal.season_top",
        service: nil,
        showsContinueWatching: true
    )
}
