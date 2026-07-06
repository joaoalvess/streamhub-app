import SwiftUI

struct ContinueWatchingRowView: View {
    let entries: [ResumeEntry]
    @Environment(DetailRouter.self) private var router: DetailRouter?

    var body: some View {
        let items = entries.map(MediaItem.init(entry:))
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text("Continue assistindo")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(Array(zip(entries, items.indices)), id: \.0.contentId) { _, index in
                        ContinueWatchingCardView(item: items[index]) {
                            open(items: items, at: index)
                        }
                    }
                }
                .padding(.leading, Theme.Metrics.edgeH)
                .padding(.trailing, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .focusSection()
        }
    }

    private func open(items: [MediaItem], at index: Int) {
        guard let router else { return }
        let row = CatalogRow(staticTitle: "Continue assistindo", style: .continueWatching, items: items)
        router.open(row: row, index: index)
    }
}

extension MediaItem {
    init(entry: ResumeEntry) {
        let service = entry.serviceCode.flatMap(StreamingService.init(rawValue:))
        self.init(
            contentId: entry.contentId,
            imdbId: entry.imdbId,
            title: entry.title,
            kind: .movie,
            genres: [],
            posterURL: entry.posterURL,
            backdropURL: entry.backdropURL,
            logoURL: entry.logoURL,
            synopsis: "",
            year: entry.year,
            serviceBadge: service?.badgeLabel,
            streamingSource: service,
            progress: entry.progress ?? 0.05,
            episodeLabel: entry.remainingLabel,
            runtime: entry.runtimeMinutes.map { "\($0) min" }
        )
    }
}
