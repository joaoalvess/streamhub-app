import SwiftUI

struct ContinueWatchingRowView: View {
    let entries: [ResumeEntry]
    @Environment(DetailRouter.self) private var router: DetailRouter?

    private struct IndexedItem: Identifiable {
        let id: String
        let index: Int
        let item: MediaItem
    }

    var body: some View {
        let items = entries.map(MediaItem.init(entry:))
        let indexed = entries.indices.map {
            IndexedItem(id: entries[$0].contentId, index: $0, item: items[$0])
        }
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text("Continue assistindo")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(indexed) { entry in
                        ContinueWatchingCardView(item: entry.item) {
                            open(items: items, at: entry.index)
                        }
                    }
                }
                .padding(.leading, Theme.Metrics.edgeH)
                .padding(.trailing, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private func open(items: [MediaItem], at index: Int) {
        guard let router else { return }
        let row = CatalogRow(staticTitle: "Continue assistindo", style: .continueWatching, items: items)
        router.open(row: row, index: index)
    }
}

nonisolated extension MediaItem {
    init(entry: ResumeEntry) {
        let service = entry.serviceCode.flatMap(StreamingService.init(rawValue:))
        let episodeLabel: String?
        if let code = entry.episodeCode {
            episodeLabel = [code, entry.remainingLabel].compactMap { $0 }.joined(separator: " · ")
        } else {
            episodeLabel = entry.remainingLabel
        }
        self.init(
            contentId: entry.metaId ?? entry.contentId,
            imdbId: entry.imdbId,
            title: entry.title,
            kind: MediaItem.Kind(rawValue: entry.mediaKind ?? "movie") ?? .movie,
            genres: entry.genres ?? [],
            posterURL: entry.posterURL,
            backdropURL: entry.backdropURL,
            logoURL: entry.logoURL,
            synopsis: entry.synopsis ?? "",
            year: entry.year,
            serviceBadge: service?.badgeLabel,
            streamingSource: service,
            progress: entry.progress ?? 0.05,
            episodeLabel: episodeLabel,
            runtime: entry.runtimeMinutes.map { "\($0) min" }
        )
    }
}
