import SwiftUI

struct EpisodesSectionView: View {
    let model: SeriesDetailViewModel
    let seriesId: String
    let ageRating: MediaItem.AgeRating?
    let progressStore: PlaybackProgressStore?
    var focus: FocusState<WindowFocus?>.Binding
    var onPlay: (EpisodeItem) -> Void
    var onRetry: () -> Void

    var body: some View {
        switch model.phase {
        case .loaded:
            section
        case .failed:
            retrySection
        case .idle, .loading, .unavailable:
            EmptyView()
        }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            if !model.seasonTabs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
                    header
                    shelf(
                        episodes: model.selectedSeason?.episodes ?? [],
                        style: .episode,
                        focusCase: WindowFocus.episode
                    )
                    .id(model.selectedSeason?.number)
                }
            }

            if let specials = model.specials {
                VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
                    Text("Especiais")
                        .font(Theme.Font.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Metrics.edgeH)

                    shelf(
                        episodes: specials.episodes,
                        style: .special,
                        focusCase: WindowFocus.special
                    )
                }
            }
        }
        .onChange(of: focus.wrappedValue) { oldValue, newValue in
            guard case .season(let index) = newValue else { return }
            if case .season = oldValue {
                model.selectSeason(index)
            } else if index != model.selectedSeasonIndex {
                focus.wrappedValue = .season(model.selectedSeasonIndex)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if model.seasonTabs.count > 1 {
            SeasonTabsView(
                seasons: model.seasonTabs,
                selectedIndex: model.selectedSeasonIndex,
                focus: focus,
                onSelect: { model.selectSeason($0) }
            )
        } else {
            Text("Episódios")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Metrics.edgeH)
        }
    }

    private func shelf(
        episodes: [EpisodeItem],
        style: EpisodeCardView.Style,
        focusCase: @escaping (Int) -> WindowFocus
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Theme.Metrics.cardSpacing) {
                ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                    EpisodeCardView(
                        episode: episode,
                        progress: model.progress(for: episode, store: progressStore, seriesId: seriesId),
                        isWatched: model.isWatched(episode, store: progressStore, seriesId: seriesId),
                        style: style,
                        ageRating: ageRating,
                        isFocused: focus.wrappedValue == focusCase(index),
                        onSelect: { onPlay(episode) }
                    )
                    .focused(focus, equals: focusCase(index))
                }
            }
            .padding(.horizontal, Theme.Metrics.edgeH)
            .padding(.vertical, Theme.Metrics.focusHeadroom)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var retrySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Episódios")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)

            Text("Não foi possível carregar os episódios.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textSecondary)

            Button("Tentar novamente", action: onRetry)
                .buttonStyle(HeroButtonStyle(shape: .capsule, isActive: focus.wrappedValue == .season(0)))
                .focused(focus, equals: .season(0))
        }
        .padding(.horizontal, Theme.Metrics.edgeH)
        .padding(.vertical, Theme.Metrics.focusHeadroom)
        .focusSection()
    }
}
