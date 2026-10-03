import Foundation

nonisolated struct NativeSessionMetadata: Equatable {
    let subtitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let synopsis: String?
    let artworkURL: URL?
    let year: Int?
    let genres: [String]
    let runtimeMinutes: Int?
    let ageRatingLabel: String?
    let ratingLabel: String?
    let cast: [MediaItem.Person]
    let directors: [MediaItem.Person]

    init(
        subtitle: String?,
        synopsis: String?,
        artworkURL: URL?,
        year: Int?,
        genres: [String],
        runtimeMinutes: Int?,
        ageRatingLabel: String?,
        ratingLabel: String?,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        cast: [MediaItem.Person] = [],
        directors: [MediaItem.Person] = []
    ) {
        self.subtitle = subtitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.synopsis = synopsis
        self.artworkURL = artworkURL
        self.year = year
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.ageRatingLabel = ageRatingLabel
        self.ratingLabel = ratingLabel
        self.cast = cast
        self.directors = directors
    }
}

nonisolated struct NativeSkipSegment: Equatable, Sendable {
    nonisolated enum Kind: Sendable {
        case intro
        case credits
        case recap
        case preview
    }

    let start: Double
    let end: Double
    let kind: Kind
}

nonisolated struct NativePlaybackSession: Identifiable, Equatable {
    let id = UUID()
    var videoURL: URL
    let title: String
    let contentKey: String?
    let startSeconds: Int?
    var metadata: NativeSessionMetadata?
    var segments: [NativeSkipSegment] = []
    var trackPreferences = TrackPreference()
}
