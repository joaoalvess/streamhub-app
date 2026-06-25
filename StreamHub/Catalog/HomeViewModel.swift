import Observation

@Observable
@MainActor
final class HomeViewModel {
    enum Phase: Sendable { case idle, loading, loaded, failed }

    private let api: MetadataAPI
    private let tag: String
    private let heroCatalogId: String
    private let maxConcurrent = 5

    private(set) var phase: Phase = .idle
    private(set) var rows: [CatalogRow] = []
    private(set) var heroItems: [MediaItem] = []

    init(tag: String = "movie",
         heroCatalogId: String = "trakt.popular.movies",
         api: MetadataAPI = MetadataAPI()) {
        self.tag = tag
        self.heroCatalogId = heroCatalogId
        self.api = api
    }

    func load() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let manifest = try await api.manifest(tag: tag)
            let defs = manifest.catalogs.filter { $0.type == tag && !$0.hasRequiredExtra }
            let pages = try await fetchPages(defs)
            guard !Task.isCancelled else { return }
            rows = pages.map {
                CatalogRow(api: api, type: $0.def.type, id: $0.def.id,
                           title: $0.def.name, style: style(for: $0.def.name), firstPage: $0.metas)
            }
            let heroMetas = pages.first { $0.def.id == heroCatalogId }?.metas ?? pages.flatMap(\.metas)
            let heroPool = heroMetas.map { MediaItem(preview: $0) }
            heroItems = Array(heroPool.filter { $0.backdropURL != nil && $0.logoURL != nil }.prefix(7))
            phase = rows.isEmpty ? .failed : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private func style(for catalogName: String) -> MediaRow.Style {
        catalogName.lowercased().starts(with: "top 10") ? .top10 : .standard
    }

    private func fetchPages(_ defs: [CatalogDefinition]) async throws
        -> [(def: CatalogDefinition, metas: [MetaPreview])] {
        try await withThrowingTaskGroup(of: (Int, [MetaPreview]).self) { group in
            var next = 0
            var inFlight = 0
            var collected: [Int: [MetaPreview]] = [:]

            func addTask(_ index: Int) {
                let def = defs[index]
                group.addTask { [api] in
                    let metas = (try? await api.catalog(type: def.type, id: def.id)) ?? []
                    return (index, metas)
                }
            }

            while next < defs.count && inFlight < maxConcurrent {
                addTask(next); next += 1; inFlight += 1
            }
            while let (index, metas) = try await group.next() {
                collected[index] = metas
                inFlight -= 1
                if next < defs.count { addTask(next); next += 1; inFlight += 1 }
            }
            return defs.indices.compactMap { index in
                guard let metas = collected[index], !metas.isEmpty else { return nil }
                return (defs[index], metas)
            }
        }
    }
}
