import Foundation

nonisolated extension MediaItem.Person {
    init(credit: CreditDTO) {
        self.init(
            name: credit.name,
            character: credit.character,
            photoURL: credit.photo.flatMap(URL.init(string:))
        )
    }
}

nonisolated extension MediaItem {
    init(
        preview: MetaPreview,
        catalogType: String? = nil,
        catalogId: String? = nil,
        service: StreamingService? = nil
    ) {
        let directors: [Person]
        if let structured = preview.appExtras?.directors, !structured.isEmpty {
            directors = structured.map(Person.init(credit:))
        } else {
            directors = Self.people(fromCSV: preview.director)
        }
        let streamingSource = service ?? catalogId.flatMap(StreamingService.init(catalogId:))

        self.init(
            contentId: preview.id,
            imdbId: preview.imdbId ?? (preview.id.hasPrefix("tt") ? preview.id : nil),
            title: preview.name,
            kind: MediaItem.Kind(rawValue: catalogType ?? "") ?? MediaItem.Kind(rawValue: preview.type) ?? .movie,
            genres: preview.genres ?? [],
            posterURL: Self.sizedPosterURL(preview.poster),
            backdropURL: preview.background.flatMap(URL.init(string:)),
            logoURL: preview.logo.flatMap(URL.init(string:)),
            synopsis: preview.description ?? "",
            year: Int(preview.year?.value ?? "") ?? 0,
            serviceBadge: streamingSource?.badgeLabel,
            streamingSource: streamingSource,
            ageRating: preview.appExtras?.certificationLocal
                .flatMap(MediaItem.AgeRating.init(rawValue:)),
            imdbRating: preview.imdbRating,
            runtime: preview.runtime,
            cast: preview.appExtras?.cast?.map(Person.init(credit:)) ?? [],
            directors: directors
        )
    }

    private static func sizedPosterURL(_ poster: String?) -> URL? {
        guard let poster else { return nil }
        let sized = poster
            .replacingOccurrences(of: "w600_and_h900_bestv2", with: "w500")
            .replacingOccurrences(of: "/t/p/original/", with: "/t/p/w500/")
        return URL(string: sized)
    }

    private static func people(fromCSV csv: String?) -> [Person] {
        guard let csv, !csv.isEmpty else { return [] }
        return csv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Person(name: $0, character: nil, photoURL: nil) }
    }
}
