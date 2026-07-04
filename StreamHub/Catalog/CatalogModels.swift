import Foundation

struct AddonManifest: Decodable, Sendable {
    let catalogs: [CatalogDefinition]
}

struct CatalogDefinition: Decodable, Sendable {
    let type: String
    let id: String
    let name: String
    let extra: [ExtraDefinition]?

    var hasRequiredExtra: Bool { extra?.contains { $0.isRequired == true } ?? false }
}

struct ExtraDefinition: Decodable, Sendable {
    let name: String
    let isRequired: Bool?
}

struct CatalogResponse: Decodable, Sendable {
    let metas: [MetaPreview]
}

struct MetaPreview: Decodable, Sendable {
    let id: String
    let type: String
    let name: String
    let description: String?
    let genres: [String]?
    let year: LenientString?
    let imdbRating: String?
    let runtime: String?
    let director: String?
    let poster: String?
    let background: String?
    let logo: String?
    let landscapePoster: String?
    let appExtras: AppExtras?
    let imdbId: String?
    let tmdbId: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, description, genres, year, imdbRating, runtime, director
        case poster, background, logo, landscapePoster
        case appExtras = "app_extras"
        case imdbId = "_imdbId"
        case tmdbId = "_tmdbId"
    }
}

struct AppExtras: Decodable, Sendable {
    let certificationLocal: String?
    let cast: [CreditDTO]?
    let directors: [CreditDTO]?
}

struct CreditDTO: Decodable, Sendable {
    let name: String
    let character: String?
    let photo: String?
}

struct LenientString: Decodable, Sendable {
    let value: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = nil
        }
    }
}
