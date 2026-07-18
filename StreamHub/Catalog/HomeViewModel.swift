import Observation

@Observable
@MainActor
final class HomeViewModel {
    enum Phase: Sendable { case idle, loading, loaded, failed }

    private nonisolated static let heroLimit = 7

    private let api: MetadataAPI
    private let config: HomeConfiguration
    private let maxConcurrent = 5

    private(set) var phase: Phase = .idle
    private(set) var rows: [CatalogRow] = []
    private(set) var heroItems: [MediaItem] = []

    init(config: HomeConfiguration, api: MetadataAPI = MetadataAPI()) {
        self.config = config
        self.api = api
    }

    func load() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        do {
            let manifest = try await api.manifest(tag: config.tag)
            let defs = manifest.catalogs.filter { config.includes($0) }
            let pages = try await fetchPages(defs)
            guard !Task.isCancelled else { return }
            rows = pages.map {
                CatalogRow(api: api, type: $0.def.type, id: $0.def.id,
                           title: config.rowTitle(for: $0.def), style: Self.style(for: $0.def),
                           firstPage: $0.metas, service: config.service)
            }
            heroItems = Self.heroPool(pages: pages, config: config)
            phase = rows.isEmpty ? .failed : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    nonisolated static func style(for def: CatalogDefinition) -> MediaRow.Style {
        if def.id.hasPrefix("flixpatrol.") { return .top10 }
        return def.name.lowercased().starts(with: "top 10") ? .top10 : .standard
    }

    nonisolated static func heroPool(
        pages: [(def: CatalogDefinition, metas: [MetaPreview])],
        config: HomeConfiguration
    ) -> [MediaItem] {
        let ordered = pages.filter { $0.def.id == config.heroCatalogId }
            + pages.filter { $0.def.id != config.heroCatalogId }
        var seen: Set<String> = []
        var pool: [MediaItem] = []
        for page in ordered {
            for meta in page.metas {
                if pool.count == Self.heroLimit { return pool }
                let item = MediaItem(
                    preview: meta,
                    catalogType: page.def.type,
                    catalogId: page.def.id,
                    service: config.service
                )
                guard item.backdropURL != nil, item.logoURL != nil else { continue }
                if let contentId = item.contentId, !seen.insert(contentId).inserted { continue }
                pool.append(item)
            }
        }
        return pool
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
