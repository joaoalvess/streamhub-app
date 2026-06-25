import Foundation

extension MediaItem {
    init(preview: MetaPreview, catalogType: String? = nil) {
        self.init(
            contentId: preview.id,
            title: preview.name,
            kind: MediaItem.Kind(rawValue: catalogType ?? preview.type) ?? .movie,
            genres: preview.genres ?? [],
            posterURL: preview.poster
                .map { $0.replacingOccurrences(of: "w600_and_h900_bestv2", with: "w500") }
                .flatMap(URL.init(string:)),
            backdropURL: preview.background.flatMap(URL.init(string:)),
            logoURL: preview.logo.flatMap(URL.init(string:)),
            synopsis: preview.description ?? "",
            year: Int(preview.year?.value ?? "") ?? 0,
            ageRating: preview.appExtras?.certificationLocal
                .flatMap(MediaItem.AgeRating.init(rawValue:))
        )
    }
}
