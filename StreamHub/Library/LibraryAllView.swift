import SwiftUI
import Observation

@Observable @MainActor
final class LibraryAllViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    private nonisolated static let pageSize = 100
    private nonisolated static let loadMoreThreshold = 30

    private(set) var phase: Phase = .loading
    private(set) var entries: [LibraryEntry] = []
    private(set) var total: Int?
    private(set) var isLoadingMore = false
    private(set) var pageFailed = false

    private let api: JellyfinAPI
    private let baseProvider: () -> URL?
    private var hasLoaded = false

    init(
        api: JellyfinAPI = JellyfinAPI(),
        baseProvider: @escaping () -> URL? = { SecretsStore.shared.jellyfinBase }
    ) {
        self.api = api
        self.baseProvider = baseProvider
    }

    var hasMore: Bool {
        Self.hasMore(count: entries.count, total: total)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await loadFirstPage()
    }

    func loadFirstPage() async {
        phase = .loading
        do {
            let page = try await api.allItems(startIndex: 0, limit: Self.pageSize)
            let base = baseProvider()
            entries = page.items.map { LibraryEntry(item: $0, base: base) }
            total = page.total
            phase = .loaded
        } catch {
            if LibraryViewModel.isCancellation(error) {
                hasLoaded = false
                return
            }
            phase = .failed
        }
    }

    func entryAppeared(_ entry: LibraryEntry) {
        guard phase == .loaded, hasMore, !isLoadingMore, !pageFailed else { return }
        guard let index = entries.firstIndex(of: entry) else { return }
        guard Self.shouldLoadMore(appearingIndex: index, count: entries.count, threshold: Self.loadMoreThreshold) else { return }
        Task { await loadNextPage() }
    }

    func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        pageFailed = false
        do {
            let page = try await api.allItems(startIndex: entries.count, limit: Self.pageSize)
            let base = baseProvider()
            entries += page.items.map { LibraryEntry(item: $0, base: base) }
            total = page.total
        } catch {
            if !LibraryViewModel.isCancellation(error) {
                pageFailed = true
            }
        }
        isLoadingMore = false
    }

    func retryPage() {
        pageFailed = false
        Task { await loadNextPage() }
    }

    nonisolated static func hasMore(count: Int, total: Int?) -> Bool {
        guard let total else { return false }
        return count < total
    }

    nonisolated static func shouldLoadMore(appearingIndex: Int, count: Int, threshold: Int) -> Bool {
        appearingIndex >= count - threshold
    }
}

struct LibraryAllView: View {
    @State private var model = LibraryAllViewModel()
    @State private var playback = LibraryPlaybackModel()
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?
    @Environment(\.dismiss) private var dismiss

    private let onSessionEnded: (() -> Void)?

    init(onSessionEnded: (() -> Void)? = nil) {
        self.onSessionEnded = onSessionEnded
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
        .task {
            playback.onSessionEnded = onSessionEnded
            await model.loadIfNeeded()
        }
        .libraryPlayback(playback, coordinator: coordinator)
        .onExitCommand { dismiss() }
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                switch model.phase {
                case .loading:
                    loadingView
                case .failed:
                    failureView
                case .loaded:
                    header
                    grid
                    footer
                }
            }
            .padding(.bottom, Theme.Metrics.rowSpacing)
        }
        .scrollClipDisabled()
    }

    private var header: some View {
        Text("Todos os títulos")
            .font(Theme.Font.screenTitle)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Metrics.edgeH)
            .padding(.top, Theme.Metrics.focusHeadroom)
    }

    private var grid: some View {
        LibraryEntryGrid(
            entries: model.entries,
            onPlay: { entry in
                playback.play(entry, coordinator: coordinator)
            },
            onEntryAppeared: { entry in
                model.entryAppeared(entry)
            }
        )
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if model.pageFailed {
            VStack(spacing: 16) {
                Text("Não foi possível carregar mais títulos.")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textSecondary)
                Button("Carregar mais") { model.retryPage() }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .focusSection()
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 220)
    }

    private var failureView: some View {
        VStack(spacing: 24) {
            Text("Não foi possível carregar a biblioteca.")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Button("Tentar novamente") {
                Task { await model.loadFirstPage() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 220)
        .focusSection()
    }
}
