import SwiftUI

struct MediaRowView: View {
    let row: CatalogRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text(row.title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(0..<row.displayCount, id: \.self) { index in
                        card(at: index)
                            .onAppear { row.onCardAppear(index) }
                    }
                }
                .padding(.leading, Theme.Metrics.edgeH)
                .padding(.trailing, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private func card(at index: Int) -> some View {
        let item = row.item(at: index)
        switch row.style {
        case .standard:
            MediaCardView(item: item)
        case .continueWatching:
            ContinueWatchingCardView(item: item)
        case .top10:
            Top10CardView(rank: row.rank(at: index), item: item)
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            ForEach(MockData.rows) { row in
                MediaRowView(row: CatalogRow(staticTitle: row.title, style: row.style, items: row.items))
            }
        }
    }
    .background(Theme.backgroundGradient)
}
