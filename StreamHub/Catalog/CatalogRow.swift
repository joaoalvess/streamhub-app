import Foundation
import Observation

@Observable
@MainActor
final class CatalogRow: Identifiable {
    private static let step = 20
    private static let prefetchThreshold = 8
    private static let bufferWatermark = 20
    private static let topRankLimit = 10

    let id = UUID()
    let title: String
    let style: MediaRow.Style

    private let api: MetadataAPI
    private let type: String
    private let catalogId: String

    private var loaded: [MediaItem]
    private var revealed: Int
    private var extraLoops = 0
    private var reachedEnd = false
    private var skip: Int
    private var isFetching = false

    init(api: MetadataAPI, type: String, id: String,
         title: String, style: MediaRow.Style, firstPage: [MetaPreview]) {
        let items = firstPage.map { MediaItem(preview: $0, catalogType: type, catalogId: id) }
        self.api = api
        self.type = type
        self.catalogId = id
        self.title = title
        self.style = style
        self.loaded = items
        self.skip = firstPage.count
        self.revealed = min(Self.step, items.count)
        if !isTopRanked { refillBufferIfNeeded() }
    }

    init(staticTitle title: String, style: MediaRow.Style, items: [MediaItem]) {
        self.api = MetadataAPI()
        self.type = ""
        self.catalogId = ""
        self.title = title
        self.style = style
        self.loaded = items
        self.skip = items.count
        self.revealed = items.count
        self.reachedEnd = true
    }

    private var isTopRanked: Bool { style == .top10 }

    var displayCount: Int {
        guard !loaded.isEmpty else { return 0 }
        if isTopRanked {
            return min(Self.topRankLimit, loaded.count)
        }
        if reachedEnd && revealed >= loaded.count {
            return loaded.count * (1 + extraLoops)
        }
        return revealed
    }

    func item(at index: Int) -> MediaItem {
        loaded[index % loaded.count]
    }

    func rank(at index: Int) -> Int {
        index % loaded.count + 1
    }

    func onCardAppear(_ index: Int) {
        guard !isTopRanked else { return }
        guard index >= displayCount - Self.prefetchThreshold else { return }
        if reachedEnd && revealed >= loaded.count {
            extraLoops += 1
        } else {
            revealed = min(revealed + Self.step, loaded.count)
            refillBufferIfNeeded()
        }
    }

    private func refillBufferIfNeeded() {
        guard !reachedEnd, !isFetching, loaded.count - revealed < Self.bufferWatermark else { return }
        isFetching = true
        Task { await fetchNextPage() }
    }

    private func fetchNextPage() async {
        let page = (try? await api.catalog(type: type, id: catalogId, skip: skip)) ?? []
        if page.isEmpty {
            reachedEnd = true
        } else {
            loaded.append(contentsOf: page.map { MediaItem(preview: $0, catalogType: type, catalogId: catalogId) })
            skip += page.count
        }
        isFetching = false
        refillBufferIfNeeded()
    }
}
