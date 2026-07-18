import Foundation

nonisolated struct MetaResponse: Decodable, Sendable {
    let meta: MetaDetail?
}

nonisolated struct MetaDetail: Decodable, Sendable {
    let id: String
    let type: String
    let name: String
    let description: String?
    let genres: [String]?
    let year: LenientString?
    let imdbRating: String?
    let runtime: String?
    let status: String?
    let poster: String?
    let background: String?
    let logo: String?
    let videos: [MetaVideo]?
    let behaviorHints: MetaBehaviorHints?
    let appExtras: AppExtras?
    let imdbId: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, description, genres, year, imdbRating, runtime, status
        case poster, background, logo, videos, behaviorHints
        case appExtras = "app_extras"
        case imdbId = "_imdbId"
    }
}

nonisolated struct MetaVideo: Decodable, Sendable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let thumbnail: String?
    let overview: String?
    let released: String?
    let available: Bool?
    let runtime: LenientString?
}

nonisolated struct MetaBehaviorHints: Decodable, Sendable {
    let defaultVideoId: String?
    let hasScheduledVideos: Bool?
}
