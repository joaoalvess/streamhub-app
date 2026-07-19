import SwiftUI

struct SearchView: View {
    @State private var model = SearchViewModel()
    @State private var router = DetailRouter()
    @Environment(RecentSearchesStore.self) private var recentsStore: RecentSearchesStore?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
        .searchable(text: searchText, prompt: Text("Filmes, séries e animes"))
        .onSubmit(of: .search) { model.submitSearch() }
        .task(id: model.searchText) { await model.searchTextChanged() }
        .task {
            model.warmUpIfNeeded()
            await model.loadExploreIfNeeded()
        }
        .environment(router)
        .fullScreenCover(item: routerTarget) { target in
            MediaWindowView(row: target.row, startIndex: target.index)
        }
    }

    private var searchText: Binding<String> {
        Binding(get: { model.searchText }, set: { model.searchText = $0 })
    }

    private var routerTarget: Binding<DetailRouter.Target?> {
        Binding(get: { router.target }, set: { router.target = $0 })
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                switch model.display {
                case .idle:
                    idleSections
                case .results:
                    resultSections
                case .loading:
                    loadingView
                case .empty:
                    noResultsView
                case .failed:
                    failureView
                }
            }
            .padding(.bottom, Theme.Metrics.rowSpacing)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var idleSections: some View {
        if let recentsStore, !recentsStore.entries.isEmpty {
            RecentSearchesRowView(
                items: recentsStore.entries.map(MediaItem.init(recent:)),
                onOpen: registerRecent
            )
        }
        if let row = model.exploreRow {
            MediaRowView(row: row)
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        ForEach(model.sections) { section in
            if !section.items.isEmpty {
                SearchResultRowView(title: section.title, items: section.items, onOpen: registerRecent)
            }
        }
        suggestionSection
    }

    @ViewBuilder
    private var suggestionSection: some View {
        if let aiSection = model.aiSection {
            SearchResultRowView(title: aiSection.title, items: aiSection.items, onOpen: registerRecent)
        } else if model.isAILoading {
            suggestionLoadingLabel
                .padding(.leading, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.rowSpacing)
        }
    }

    private var suggestionLoadingLabel: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Buscando sugestões…")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textTertiary)
        }
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
            if model.isAILoading {
                suggestionLoadingLabel
                    .padding(.top, 12)
            }
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

    private func registerRecent(_ item: MediaItem) {
        recentsStore?.record(item)
    }
}
