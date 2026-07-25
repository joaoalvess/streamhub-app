import SwiftUI
import Observation

@Observable @MainActor
final class LibrarySearchViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed
    }

    private nonisolated static let minQueryLength = 2
    private nonisolated static let resultLimit = 60

    var searchText = ""
    private(set) var phase: Phase = .idle
    private(set) var entries: [LibraryEntry] = []
    private(set) var activeQuery: String?

    private let api: JellyfinAPI
    private let baseProvider: () -> URL?
    private let debounce: Duration

    init(
        api: JellyfinAPI = JellyfinAPI(),
        debounce: Duration = .milliseconds(300),
        baseProvider: @escaping () -> URL? = { SecretsStore.shared.jellyfinBase }
    ) {
        self.api = api
        self.debounce = debounce
        self.baseProvider = baseProvider
    }

    func searchTextChanged() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minQueryLength else {
            activeQuery = nil
            entries = []
            phase = .idle
            return
        }
        guard (try? await Task.sleep(for: debounce)) != nil else { return }
        guard !Task.isCancelled else { return }
        await search(query: query)
    }

    func retry() {
        guard let query = activeQuery else { return }
        Task { await search(query: query) }
    }

    private func search(query: String) async {
        activeQuery = query
        phase = .loading
        do {
            let items = try await api.search(term: query, limit: Self.resultLimit)
            guard !Task.isCancelled, activeQuery == query else { return }
            let base = baseProvider()
            entries = items.map { LibraryEntry(item: $0, base: base) }
            phase = entries.isEmpty ? .empty : .loaded
        } catch {
            guard activeQuery == query, !LibraryViewModel.isCancellation(error) else { return }
            entries = []
            phase = .failed
        }
    }
}

struct LibrarySearchView: View {
    @State private var model = LibrarySearchViewModel()
    @State private var playback = LibraryPlaybackModel()
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?
    @Environment(\.dismiss) private var dismiss

    private let onSessionEnded: (() -> Void)?

    init(onSessionEnded: (() -> Void)? = nil) {
        self.onSessionEnded = onSessionEnded
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                content
            }
            .searchable(text: searchText, prompt: Text("Buscar na biblioteca"))
            .task(id: model.searchText) { await model.searchTextChanged() }
        }
        .task { playback.onSessionEnded = onSessionEnded }
        .libraryPlayback(playback, coordinator: coordinator)
        .onExitCommand { dismiss() }
    }

    private var searchText: Binding<String> {
        Binding(get: { model.searchText }, set: { model.searchText = $0 })
    }

    private var content: some View {
        ScrollView(.vertical) {
            switch model.phase {
            case .idle:
                hintView
            case .loading:
                loadingView
            case .loaded:
                resultsGrid
            case .empty:
                noResultsView
            case .failed:
                failureView
            }
        }
        .scrollClipDisabled()
    }

    private var resultsGrid: some View {
        LibraryEntryGrid(entries: model.entries) { entry in
            playback.play(entry, coordinator: coordinator)
        }
    }

    private var hintView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text("Busque um título da sua biblioteca")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 220)
    }

    private var noResultsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text("Nenhum resultado para “\(model.activeQuery ?? "")”")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("Verifique a ortografia ou tente outros termos.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var failureView: some View {
        VStack(spacing: 24) {
            Text("Não foi possível concluir a busca.")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Button("Tentar novamente") { model.retry() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 220)
        .focusSection()
    }
}

struct LibraryEntryGrid: View {
    let entries: [LibraryEntry]
    var onPlay: (LibraryEntry) -> Void
    var onEntryAppeared: ((LibraryEntry) -> Void)?

    private let columns = [
        GridItem(
            .adaptive(minimum: Theme.Size.posterWidth, maximum: Theme.Size.posterWidth),
            spacing: Theme.Metrics.cardSpacing
        )
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Metrics.cardSpacing) {
            ForEach(entries) { entry in
                LibraryCardView(entry: entry) {
                    onPlay(entry)
                }
                .onAppear { onEntryAppeared?(entry) }
            }
        }
        .padding(.horizontal, Theme.Metrics.edgeH)
        .padding(.vertical, Theme.Metrics.focusHeadroom)
    }
}
