import SwiftUI

struct RecentSearchesRowView: View {
    let items: [MediaItem]
    var onOpen: (MediaItem) -> Void = { _ in }
    var onRemove: (MediaItem) -> Void = { _ in }
    var onClear: () -> Void = {}
    @Environment(DetailRouter.self) private var router: DetailRouter?
    @FocusState private var focusedId: String?
    @FocusState private var isClearFocused: Bool

    private struct IndexedItem: Identifiable {
        let id: String
        let index: Int
        let item: MediaItem
    }

    var body: some View {
        let indexed = items.indices.map {
            IndexedItem(id: items[$0].searchIdentity, index: $0, item: items[$0])
        }
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            HStack(spacing: 16) {
                Text("Buscas Recentes")
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                Button("Limpar", action: onClear)
                    .buttonStyle(ClearButtonStyle(isFocused: isClearFocused))
                    .focused($isClearFocused)
            }
            .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(indexed) { entry in
                        RecentSearchCardView(item: entry.item, isFocused: focusedId == entry.id) {
                            open(at: entry.index)
                        }
                        .focused($focusedId, equals: entry.id)
                        .contextMenu {
                            Button("Remover", role: .destructive) {
                                onRemove(entry.item)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private func open(at index: Int) {
        guard let router, items.indices.contains(index) else { return }
        onOpen(items[index])
        let row = CatalogRow(staticTitle: "Buscas Recentes", style: .standard, items: items)
        router.open(row: row, index: index)
    }
}

private struct ClearButtonStyle: ButtonStyle {
    var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.meta)
            .foregroundStyle(isFocused ? Color.black : Theme.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background {
                Capsule().fill(isFocused ? Theme.fill : Color.clear)
            }
            .animation(.easeOut(duration: 0.18)) { view in
                view.scaleEffect(configuration.isPressed ? 1.04 : (isFocused ? 1.08 : 1.0))
            }
    }
}
