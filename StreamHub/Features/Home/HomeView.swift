import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @FocusState private var focusedControl: HeroControl?
    @State private var heroTint: Color = Theme.bg
    @Environment(PlaybackProgressStore.self) private var progressStore: PlaybackProgressStore?
    @Environment(MyListStore.self) private var myList: MyListStore?
    @Environment(DetailRouter.self) private var router: DetailRouter?

    private let config: HomeConfiguration

    init(config: HomeConfiguration) {
        self.config = config
        _viewModel = State(initialValue: HomeViewModel(config: config))
    }

    private enum ScrollAnchor: Hashable { case top }

    var body: some View {
        ZStack {
            Theme.homeBackground(tint: heroTint)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: heroTint)

            switch viewModel.phase {
            case .idle, .loading:
                ProgressView()
            case .failed:
                failureView
            case .loaded:
                content
            }
        }
        .ignoresSafeArea()
        .task { await viewModel.load() }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                    HeroView(
                        items: viewModel.heroItems,
                        focusedControl: $focusedControl,
                        heroTint: $heroTint,
                        onPlay: { openHero(at: $0, autoplay: true) },
                        onInfo: { openHero(at: $0, autoplay: false) },
                        onToggleMyList: { myList?.toggle($0) },
                        isInMyList: { myList?.contains($0) ?? false }
                    )
                        .id(ScrollAnchor.top)
                        .containerRelativeFrame(.vertical) { height, _ in height }
                        .padding(.bottom, -Theme.Metrics.heroOverlap)
                        .zIndex(0)

                    if config.showsContinueWatching, let progressStore, !progressStore.entries.isEmpty {
                        ContinueWatchingRowView(
                            entries: progressStore.entries,
                            onRemove: { progressStore.remove(contentId: $0) }
                        )
                            .zIndex(1)
                    }

                    if config.showsContinueWatching, let myList, !myList.entries.isEmpty {
                        MyListRowView(entries: myList.entries, onRemove: { myList.remove(contentId: $0) })
                            .zIndex(1)
                    }

                    ForEach(viewModel.rows) { row in
                        MediaRowView(row: row)
                            .zIndex(1)
                    }
                }
            }
            .onChange(of: focusedControl) { _, control in
                if control != nil {
                    withAnimation { proxy.scrollTo(ScrollAnchor.top, anchor: .top) }
                }
            }
            .defaultFocus($focusedControl, .play)
        }
    }

    private func openHero(at index: Int, autoplay: Bool) {
        let items = viewModel.heroItems
        guard let router, items.indices.contains(index) else { return }
        let row = CatalogRow(staticTitle: "Destaques", style: .standard, items: items)
        router.open(row: row, index: index, autoplay: autoplay)
    }

    private var failureView: some View {
        VStack(spacing: 24) {
            Text("Não foi possível carregar o conteúdo.")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Button("Tentar novamente") {
                Task { await viewModel.load() }
            }
        }
    }
}

#Preview {
    HomeView(config: .filmes)
        .preferredColorScheme(.dark)
}
