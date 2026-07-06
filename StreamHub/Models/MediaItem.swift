import Foundation
import SwiftUI

nonisolated struct MediaItem: Identifiable, Hashable {
    let id: UUID
    let contentId: String?
    let imdbId: String?
    let title: String
    let kind: Kind
    let genres: [String]
    let posterURL: URL?
    let backdropURL: URL?
    let logoURL: URL?
    let synopsis: String
    let year: Int
    let serviceBadge: String?
    let streamingSource: StreamingService?
    let progress: Double?
    let episodeLabel: String?
    let tint: Color?
    let ageRating: AgeRating?
    let imdbRating: String?
    let runtime: String?
    let cast: [Person]
    let directors: [Person]

    nonisolated enum Kind: String {
        case movie
        case series
        case anime
    }

    nonisolated struct Person: Hashable {
        let name: String
        let character: String?
        let photoURL: URL?
    }

    nonisolated enum AgeRating: String {
        case l = "L"
        case ten = "10"
        case twelve = "12"
        case fourteen = "14"
        case sixteen = "16"
        case eighteen = "18"

        var label: String {
            self == .l ? rawValue : "A" + rawValue
        }

        var color: Color {
            switch self {
            case .l: return Color(hex: 0x3AAA35)
            case .ten: return Color(hex: 0x0A75BD)
            case .twelve: return Color(hex: 0xF4B400)
            case .fourteen: return Color(hex: 0xF07F09)
            case .sixteen: return Color(hex: 0xE1141D)
            case .eighteen: return Color(hex: 0x1A1A1A)
            }
        }
    }

    init(
        id: UUID = UUID(),
        contentId: String? = nil,
        imdbId: String? = nil,
        title: String,
        kind: Kind,
        genres: [String],
        posterURL: URL?,
        backdropURL: URL?,
        logoURL: URL? = nil,
        synopsis: String,
        year: Int,
        serviceBadge: String? = nil,
        streamingSource: StreamingService? = nil,
        progress: Double? = nil,
        episodeLabel: String? = nil,
        tint: Color? = nil,
        ageRating: AgeRating? = nil,
        imdbRating: String? = nil,
        runtime: String? = nil,
        cast: [Person] = [],
        directors: [Person] = []
    ) {
        self.id = id
        self.contentId = contentId
        self.imdbId = imdbId
        self.title = title
        self.kind = kind
        self.genres = genres
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.synopsis = synopsis
        self.year = year
        self.serviceBadge = serviceBadge
        self.streamingSource = streamingSource
        self.progress = progress
        self.episodeLabel = episodeLabel
        self.tint = tint
        self.ageRating = ageRating
        self.imdbRating = imdbRating
        self.runtime = runtime
        self.cast = cast
        self.directors = directors
    }
}
