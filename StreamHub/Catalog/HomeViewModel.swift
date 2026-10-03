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

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(config: HomeConfiguration, api: MetadataAPI = MetadataAPI()) {
        self.config = config
        self.api = api
    }

    func load() async {
        if loadTask == nil, phase != .loaded {
            loadTask = Task { await performLoad() }
        }
        if let loadTask {
            await loadTask.value
        }
    }

    private func performLoad() async {
        defer { loadTask = nil }
        phase = .loading
        guard let manifest = try? await api.manifest(tag: config.tag) else {
            phase = .failed
            return
        }
        await fetchRows(manifest.catalogs.filter { config.includes($0) })
        phase = rows.isEmpty ? .failed : .loaded
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

    nonisolated static func fetchOrder(count: Int, heroIndex: Int?) -> [Int] {
        guard let heroIndex, (0..<count).contains(heroIndex) else { return Array(0..<count) }
        return [heroIndex] + (0..<count).filter { $0 != heroIndex }
    }

    nonisolated static func extendedHero(_ current: [MediaItem], with candidates: [MediaItem]) -> [MediaItem] {
        var seen = Set(current.map(heroKey))
        var extended = current
        for candidate in candidates where extended.count < Self.heroLimit {
            if seen.insert(heroKey(candidate)).inserted {
                extended.append(candidate)
            }
        }
        return extended
    }

    private nonisolated static func heroKey(_ item: MediaItem) -> String {
        item.contentId ?? item.title
    }

    private func fetchRows(_ defs: [CatalogDefinition]) async {
        let heroIndex = defs.firstIndex { $0.id == config.heroCatalogId }
        var pending = Self.fetchOrder(count: defs.count, heroIndex: heroIndex)[...]
        var pages: [Int: [MetaPreview]] = [:]
        var built: [Int: CatalogRow] = [:]

        await withTaskGroup(of: (Int, [MetaPreview]).self) { group in
            func addNext() {
                guard let index = pending.popFirst() else { return }
                let def = defs[index]
                group.addTask { [api] in
                    let metas = (try? await api.catalog(type: def.type, id: def.id)) ?? []
                    return (index, metas)
                }
            }

            for _ in 0..<maxConcurrent { addNext() }
            while let (index, metas) = await group.next() {
                pages[index] = metas
                if !metas.isEmpty {
                    built[index] = makeRow(defs[index], firstPage: metas)
                }
                let visible = defs.indices.prefix { pages[$0] != nil }.compactMap { built[$0] }
                if visible.count != rows.count { rows = visible }
                let heroSettled = heroIndex.map { pages[$0] != nil } ?? true
                if heroSettled {
                    extendHero(defs: defs, pages: pages)
                    if phase == .loading, !rows.isEmpty || !heroItems.isEmpty { phase = .loaded }
                }
                addNext()
            }
        }
    }

    private func makeRow(_ def: CatalogDefinition, firstPage: [MetaPreview]) -> CatalogRow {
        CatalogRow(api: api, type: def.type, id: def.id,
                   title: config.rowTitle(for: def), style: Self.style(for: def),
                   firstPage: firstPage, service: config.service)
    }

    private func extendHero(defs: [CatalogDefinition], pages: [Int: [MetaPreview]]) {
        guard heroItems.count < Self.heroLimit else { return }
        let arrived = defs.indices.compactMap { index -> (def: CatalogDefinition, metas: [MetaPreview])? in
            guard let metas = pages[index], !metas.isEmpty else { return nil }
            return (defs[index], metas)
        }
        let extended = Self.extendedHero(heroItems, with: Self.heroPool(pages: arrived, config: config))
        if extended.count != heroItems.count {
            heroItems = extended
        }
    }
}
