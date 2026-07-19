import Foundation
import Observation

nonisolated struct SearchSection: Identifiable {
    enum ID: String, CaseIterable { case movies, series, anime, suggestions }
    enum Phase: Equatable { case idle, loading, loaded, empty, failed }

    let id: ID
    var phase: Phase
    var items: [MediaItem]

    var title: String {
        switch id {
        case .movies: "Filmes"
        case .series: "Séries"
        case .anime: "Animes"
        case .suggestions: "Sugestões"
        }
    }
}

@Observable
@MainActor
final class SearchViewModel {
    enum Display { case idle, loading, results, empty, failed }

    private nonisolated static let minQueryLength = 2
    private nonisolated static let aiWordThreshold = 3
    private nonisolated static let exploreLimit = 20

    private nonisolated enum FetchOutcome {
        case success([MetaPreview])
        case failure
    }

    var searchText = ""

    private(set) var sections: [SearchSection] = [
        SearchSection(id: .movies, phase: .idle, items: []),
        SearchSection(id: .series, phase: .idle, items: []),
        SearchSection(id: .anime, phase: .idle, items: [])
    ]
    private(set) var aiSection: SearchSection?
    private(set) var isAILoading = false
    private(set) var activeQuery: String?
    private(set) var exploreRow: CatalogRow?

    private let api: MetadataAPI
    private let debounce: Duration
    private var aiTask: Task<Void, Never>?
    private var aiQuery: String?
    private var didWarmUp = false

    init(api: MetadataAPI = MetadataAPI(), debounce: Duration = .milliseconds(300)) {
        self.api = api
        self.debounce = debounce
    }

    var display: Display {
        guard activeQuery != nil else { return .idle }
        if sections.contains(where: { !$0.items.isEmpty }) || aiSection != nil { return .results }
        let phases = sections.map(\.phase)
        if phases.contains(.loading) { return .loading }
        if phases.allSatisfy({ $0 == .failed }) { return .failed }
        return .empty
    }

    func searchTextChanged() async {
        let query = Self.normalized(searchText)
        guard query.count >= Self.minQueryLength else {
            clearResults()
            return
        }
        guard (try? await Task.sleep(for: debounce)) != nil else { return }
        guard !Task.isCancelled else { return }
        await performTitleSearch(query: query)
    }

    func submitSearch() {
        let query = Self.normalized(searchText)
        guard query.count >= Self.minQueryLength else { return }
        startAISearch(query: query)
    }

    func retry() {
        guard let query = activeQuery else { return }
        Task { await performTitleSearch(query: query) }
    }

    func warmUpIfNeeded() {
        guard !didWarmUp else { return }
        didWarmUp = true
        Task { [api] in
            _ = try? await api.manifest()
        }
    }

    func loadExploreIfNeeded() async {
        guard exploreRow == nil else { return }
        async let movies = exploreCatalog(type: "movie", id: "mdblist.2236")
        async let shows = exploreCatalog(type: "series", id: "trakt.trending.shows")
        async let anime = exploreCatalog(type: "anime", id: "mal.season_top")
        let groups = await [movies, shows, anime]
        guard !Task.isCancelled, exploreRow == nil else { return }
        let merged = Self.interleaved(groups, limit: Self.exploreLimit)
        guard !merged.isEmpty else { return }
        exploreRow = CatalogRow(staticTitle: "Explore", style: .standard, items: merged)
    }

    private func performTitleSearch(query: String) async {
        if activeQuery != query { cancelAI() }
        activeQuery = query
        for index in sections.indices {
            sections[index].phase = .loading
        }
        async let movies = fetch(type: "movie", id: "search.movie", query: query)
        async let shows = fetch(type: "series", id: "search.series", query: query)
        async let animeSeries = fetch(type: "anime.series", id: "search.anime_series", query: query)
        async let animeMovies = fetch(type: "anime.movie", id: "search.anime_movie", query: query)
        let outcomes = await (movies: movies, shows: shows, animeSeries: animeSeries, animeMovies: animeMovies)
        guard !Task.isCancelled, activeQuery == query else { return }
        apply(outcomes.movies, to: .movies, catalogType: "movie", catalogId: "search.movie")
        apply(outcomes.shows, to: .series, catalogType: "series", catalogId: "search.series")
        applyAnime(series: outcomes.animeSeries, movies: outcomes.animeMovies)
        if Self.shouldAutoTriggerAI(query: query, resultsEmpty: titleResultsAreEmpty) {
            startAISearch(query: query)
        }
    }

    private func fetch(type: String, id: String, query: String) async -> FetchOutcome {
        do {
            return .success(try await api.search(type: type, id: id, query: query))
        } catch {
            return .failure
        }
    }

    private func apply(_ outcome: FetchOutcome, to id: SearchSection.ID,
                       catalogType: String, catalogId: String) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        switch outcome {
        case .failure:
            sections[index].items = []
            sections[index].phase = .failed
        case .success(let previews):
            let mapped = Self.dedupedById(previews).map {
                MediaItem(preview: $0, catalogType: catalogType, catalogId: catalogId)
            }
            sections[index].items = Self.reconciled(mapped, with: sections[index].items)
            sections[index].phase = mapped.isEmpty ? .empty : .loaded
        }
    }

    private func applyAnime(series: FetchOutcome, movies: FetchOutcome) {
        guard let index = sections.firstIndex(where: { $0.id == .anime }) else { return }
        var previews: [MetaPreview] = []
        var succeeded = false
        if case .success(let items) = series {
            previews += items
            succeeded = true
        }
        if case .success(let items) = movies {
            previews += items
            succeeded = true
        }
        guard succeeded else {
            sections[index].items = []
            sections[index].phase = .failed
            return
        }
        let mapped = Self.dedupedById(previews).map {
            MediaItem(preview: $0, catalogType: "anime", catalogId: "search.anime_series")
        }
        sections[index].items = Self.reconciled(mapped, with: sections[index].items)
        sections[index].phase = mapped.isEmpty ? .empty : .loaded
    }

    private func startAISearch(query: String) {
        guard aiQuery != query else { return }
        cancelAI()
        aiQuery = query
        isAILoading = true
        aiTask = Task { [api] in
            let outcome: FetchOutcome
            do {
                outcome = .success(try await api.search(type: "other", id: "gemini.search", query: query))
            } catch {
                outcome = .failure
            }
            guard !Task.isCancelled else { return }
            applyAI(outcome, query: query)
        }
    }

    private func applyAI(_ outcome: FetchOutcome, query: String) {
        guard aiQuery == query else { return }
        isAILoading = false
        switch outcome {
        case .failure:
            aiQuery = nil
            aiSection = nil
        case .success(let previews):
            let mapped = Self.dedupedById(previews).map {
                MediaItem(preview: $0, catalogId: "gemini.search")
            }
            let fresh = Self.dedupedAgainstShown(mapped, shownIds: shownTitleIds)
            aiSection = fresh.isEmpty
                ? nil
                : SearchSection(id: .suggestions, phase: .loaded, items: fresh)
        }
    }

    private func cancelAI() {
        aiTask?.cancel()
        aiTask = nil
        aiQuery = nil
        isAILoading = false
        aiSection = nil
    }

    private func clearResults() {
        cancelAI()
        activeQuery = nil
        for index in sections.indices {
            sections[index].items = []
            sections[index].phase = .idle
        }
    }

    private func exploreCatalog(type: String, id: String) async -> [MediaItem] {
        let previews = (try? await api.catalog(type: type, id: id)) ?? []
        return previews.map { MediaItem(preview: $0, catalogType: type, catalogId: id) }
    }

    private var shownTitleIds: Set<String> {
        var ids: Set<String> = []
        for section in sections {
            for item in section.items {
                if let contentId = item.contentId { ids.insert(contentId) }
                if let imdbId = item.imdbId { ids.insert(imdbId) }
            }
        }
        return ids
    }

    private var titleResultsAreEmpty: Bool {
        sections.allSatisfy { $0.items.isEmpty }
    }

    nonisolated static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func shouldAutoTriggerAI(query: String, resultsEmpty: Bool) -> Bool {
        if resultsEmpty { return true }
        let words = query.split(separator: " ").filter { !$0.isEmpty }
        return words.count >= aiWordThreshold
    }

    nonisolated static func dedupedById(_ previews: [MetaPreview]) -> [MetaPreview] {
        var seen: Set<String> = []
        return previews.filter { seen.insert($0.id).inserted }
    }

    nonisolated static func reconciled(_ incoming: [MediaItem], with existing: [MediaItem]) -> [MediaItem] {
        var byContentId: [String: MediaItem] = [:]
        for item in existing {
            if let key = item.contentId {
                byContentId[key] = item
            }
        }
        return incoming.map { item in
            guard let key = item.contentId, let previous = byContentId[key] else { return item }
            return previous
        }
    }

    nonisolated static func dedupedAgainstShown(_ items: [MediaItem], shownIds: Set<String>) -> [MediaItem] {
        items.filter { item in
            let keys = [item.contentId, item.imdbId].compactMap { $0 }
            return keys.allSatisfy { !shownIds.contains($0) }
        }
    }

    nonisolated static func interleaved(_ groups: [[MediaItem]], limit: Int) -> [MediaItem] {
        var result: [MediaItem] = []
        var seen: Set<String> = []
        var index = 0
        while result.count < limit, groups.contains(where: { index < $0.count }) {
            for group in groups where index < group.count && result.count < limit {
                let item = group[index]
                let key = item.contentId ?? item.imdbId ?? item.id.uuidString
                if seen.insert(key).inserted {
                    result.append(item)
                }
            }
            index += 1
        }
        return result
    }
}
