import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @FocusState private var focusedControl: HeroControl?
    @State private var heroTint: Color = Theme.bg

    init(tag: String = "movie", heroCatalogId: String = "trakt.popular.movies") {
        _viewModel = State(initialValue: HomeViewModel(tag: tag, heroCatalogId: heroCatalogId))
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
                    HeroView(items: viewModel.heroItems, focusedControl: $focusedControl, heroTint: $heroTint)
                        .id(ScrollAnchor.top)
                        .containerRelativeFrame(.vertical) { height, _ in height }
                        .padding(.bottom, -Theme.Metrics.heroOverlap)
                        .zIndex(0)

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

    private var failureView: some View {
        VStack(spacing: 24) {
            Text("Não foi possível carregar os filmes.")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Button("Tentar novamente") {
                Task { await viewModel.load() }
            }
        }
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
