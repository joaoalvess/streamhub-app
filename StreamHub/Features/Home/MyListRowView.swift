import SwiftUI

struct MyListRowView: View {
    let entries: [MyListEntry]
    var onRemove: (String) -> Void = { _ in }
    @Environment(DetailRouter.self) private var router: DetailRouter?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    private struct IndexedItem: Identifiable {
        let id: String
        let index: Int
        let item: MediaItem
    }

    var body: some View {
        let indexed = entries.enumerated().map { index, entry in
            IndexedItem(id: entry.contentId, index: index, item: MediaItem(myList: entry))
        }
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text("Minha lista")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metrics.cardSpacing) {
                    ForEach(indexed) { entry in
                        MediaCardView(item: entry.item) {
                            open(at: entry.index)
                        }
                        .contextMenu {
                            Button("Remover da Minha lista", role: .destructive) {
                                toasts?.show("Removido da Minha lista", systemImage: "xmark")
                                onRemove(entry.id)
                            }
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

    private func open(at index: Int) {
        guard let router else { return }
        router.open(row: .myList(entries: entries), index: index)
    }
}

extension CatalogRow {
    static func myList(entries: [MyListEntry]) -> CatalogRow {
        CatalogRow(
            staticTitle: "Minha lista",
            style: .standard,
            items: entries.map(MediaItem.init(myList:))
        )
    }
}
