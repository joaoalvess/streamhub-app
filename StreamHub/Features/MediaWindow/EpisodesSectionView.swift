import SwiftUI

struct EpisodesSectionView: View {
    let model: SeriesDetailViewModel
    let seriesId: String
    let ageRating: MediaItem.AgeRating?
    let progressStore: PlaybackProgressStore?
    var focus: FocusState<WindowFocus?>.Binding
    var onPlay: (EpisodeItem) -> Void
    var onRetry: () -> Void

    @Environment(ToastCenter.self) private var toasts: ToastCenter?
    @State private var didRedirect = false

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
                    ScrollViewReader { proxy in
                        shelf(
                            episodes: model.selectedSeason?.episodes ?? [],
                            style: .episode,
                            focusCase: WindowFocus.episode
                        )
                        .task(id: model.selectedSeason?.number) {
                            didRedirect = false
                            guard let next = nextEpisodeInSelectedSeason else { return }
                            proxy.scrollTo(next.id, anchor: .center)
                        }
                    }
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
            if case .episode(let index) = newValue {
                redirectToNextEpisode(from: oldValue, landedAt: index)
                return
            }
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
        let seriesProgress = model.seriesProgress(store: progressStore, seriesId: seriesId)
        let focused = focus.wrappedValue
        let seasonVideoIds = style == .episode ? releasedVideoIds(in: model.selectedSeason) : []
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Theme.Metrics.cardSpacing) {
                ForEach(episodes) { episode in
                    let index = model.position(of: episode) ?? 0
                    let isWatched = seriesProgress.isWatched(episode)
                    EpisodeCardView(
                        episode: episode,
                        progress: seriesProgress.progress(for: episode),
                        isWatched: isWatched,
                        style: style,
                        ageRating: ageRating,
                        isFocused: focused == focusCase(index),
                        onSelect: { onPlay(episode) }
                    )
                    .focused(focus, equals: focusCase(index))
                    .contextMenu {
                        if episode.isReleased {
                            Button(isWatched ? "Marcar como não assistido" : "Marcar como assistido") {
                                toggleWatched(episode)
                            }
                        }
                        if seasonVideoIds.contains(where: { !seriesProgress.watched.contains($0) }) {
                            Button("Marcar temporada como assistida") {
                                markSeasonWatched(seasonVideoIds)
                            }
                        }
                        if seasonVideoIds.contains(where: { seriesProgress.watched.contains($0) }) {
                            Button("Desmarcar temporada") {
                                unmarkSeasonWatched(seasonVideoIds)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.edgeH)
            .padding(.vertical, Theme.Metrics.focusHeadroom)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var nextEpisodeInSelectedSeason: EpisodeItem? {
        guard let next = model.seriesProgress(store: progressStore, seriesId: seriesId).next,
              let season = model.selectedSeason,
              season.episodes.contains(where: { $0.videoId == next.videoId }) else { return nil }
        return next
    }

    private func redirectToNextEpisode(from oldValue: WindowFocus?, landedAt index: Int) {
        if case .episode = oldValue { return }
        guard !didRedirect else { return }
        didRedirect = true
        guard let next = nextEpisodeInSelectedSeason,
              let nextIndex = model.position(of: next),
              nextIndex != index else { return }
        focus.wrappedValue = .episode(nextIndex)
    }

    private func releasedVideoIds(in season: SeasonGroup?) -> [String] {
        season?.episodes.filter(\.isReleased).map(\.videoId) ?? []
    }

    private func nextRef(after episode: EpisodeItem) -> NextEpisodeRef? {
        model.episodeAfter(episode).map {
            NextEpisodeRef(
                videoId: $0.videoId,
                season: $0.season,
                episode: $0.episode,
                title: $0.title,
                runtimeMinutes: $0.runtimeMinutes
            )
        }
    }

    private func toggleWatched(_ episode: EpisodeItem) {
        guard let progressStore else { return }
        progressStore.toggleWatched(seriesId: seriesId, videoId: episode.videoId, next: nextRef(after: episode))
        let watched = progressStore.isWatched(seriesId: seriesId, videoId: episode.videoId)
        toasts?.show(
            watched ? "Marcado como assistido" : "Marcado como não assistido",
            systemImage: watched ? "checkmark" : "xmark"
        )
    }

    private func markSeasonWatched(_ videoIds: [String]) {
        guard let progressStore,
              let last = model.selectedSeason?.episodes.last(where: \.isReleased) else { return }
        progressStore.markSeasonWatched(seriesId: seriesId, videoIds: videoIds, next: nextRef(after: last))
        toasts?.show("Temporada marcada como assistida", systemImage: "checkmark")
    }

    private func unmarkSeasonWatched(_ videoIds: [String]) {
        guard let progressStore else { return }
        progressStore.unmarkSeasonWatched(seriesId: seriesId, videoIds: videoIds)
        toasts?.show("Temporada desmarcada", systemImage: "xmark")
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
