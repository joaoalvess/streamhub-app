import SwiftUI
import ImageIO

/// Tela intermediária ao selecionar um título. Apresenta um carrossel de
/// backdrops (window) que expande para fullscreen ao pressionar cima/baixo ou
/// o botão central. Voltar: ficha completa → fullscreen → window → home.
struct MediaWindowView: View {
    static let expandDuration: TimeInterval = 0.55

    let row: CatalogRow
    let startIndex: Int

    @State private var centerIndex: Int
    @State private var isFullscreen = false
    @State private var showsInfo = false
    @State private var showsSources = false
    @State private var sourcesTarget: PlayTarget?
    @State private var loaded: Loaded?
    @State private var playbackMode: PlaybackMode = .dubbed
    @State private var seriesModel = SeriesDetailViewModel()
    @FocusState private var focus: WindowFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?
    @Environment(MetaProvider.self) private var metaProvider: MetaProvider?

    private enum ScrollAnchor: Hashable { case top, episodes }

    init(row: CatalogRow, startIndex: Int) {
        self.row = row
        self.startIndex = startIndex
        _centerIndex = State(initialValue: max(0, startIndex))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                BackdropCarousel(
                    row: row,
                    centerIndex: $centerIndex,
                    isFullscreen: isFullscreen,
                    focus: $focus,
                    onExpand: enterFullscreen
                )
                .padding(.top, 50)

                if let loaded {
                    HeroCard(
                        item: loaded.item,
                        backdrop: loaded.backdrop,
                        isFullscreen: isFullscreen
                    )
                    .frame(width: isFullscreen ? geo.size.width : geo.size.width * 0.9)
                    .padding(.top, isFullscreen ? 0 : 50)
                    .allowsHitTesting(false)
                    .transition(.opacity)

                    if isFullscreen, showsEpisodeSection {
                        Color.black
                            .opacity(isEpisodesFocus ? 0.85 : 0)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.35), value: isEpisodesFocus)

                        episodePages(for: loaded, size: geo.size)
                            .allowsHitTesting(isFullscreen)
                            .disabled(showsInfo || showsSources)
                            .transition(.opacity.combined(with: .offset(y: 16)))
                    } else {
                        overlayView(for: loaded)
                            .frame(width: isFullscreen ? geo.size.width : geo.size.width * 0.9)
                            .allowsHitTesting(isFullscreen)
                            .disabled(showsInfo || showsSources)
                            .transition(.opacity.combined(with: .offset(y: 16)))
                    }

                    if showsInfo {
                        InfoModalView(item: loaded.item)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }

                    if showsSources, let target = sourcesTarget {
                        SourcesModalView(
                            mode: playbackMode,
                            loadSources: { await loadSources(for: target, item: loaded.item) },
                            onSelect: { selectSource($0, item: loaded.item) }
                        )
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .defaultFocus($focus, .carousel)
        .onExitCommand(perform: handleBack)
        .animation(.smooth(duration: Self.expandDuration), value: isFullscreen)
        .onChange(of: centerIndex) { _, _ in
            withAnimation(.easeOut(duration: 0.25)) { loaded = nil }
        }
        .task(id: centerIndex) { await loadAssets() }
        .task(id: centerIndex) { await loadSeries() }
        .alert("Não foi possível reproduzir", isPresented: playbackAlertPresented) {
            Button("OK", role: .cancel) { coordinator?.dismissError() }
        } message: {
            Text(playbackErrorMessage ?? "")
        }
    }

    private var isPlayLoading: Bool {
        coordinator?.state == .loading
    }

    private var showsEpisodeSection: Bool {
        switch seriesModel.phase {
        case .loaded:
            !seriesModel.seasons.isEmpty
        case .failed:
            true
        case .idle, .loading, .unavailable:
            false
        }
    }

    private func overlayView(for loaded: Loaded) -> some View {
        WindowInfoOverlay(
            item: loaded.item,
            logo: loaded.logo,
            focus: $focus,
            playLabel: playLabel(for: loaded.item),
            isPlayLoading: isPlayLoading,
            isPlayEnabled: isPlayEnabled(for: loaded.item),
            showsModeSelector: showsModeSelector(for: loaded.item),
            playbackMode: playbackMode,
            onPlay: { play(loaded.item) },
            onCycleMode: {
                guard !showsSources else { return }
                playbackMode = playbackMode.next
            },
            onHoldMode: { holdMode(loaded.item) },
            onShowDetails: showDetails
        )
    }

    private func episodePages(for loaded: Loaded, size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                    overlayView(for: loaded)
                        .frame(width: size.width)
                        .containerRelativeFrame(.vertical)
                        .id(ScrollAnchor.top)

                    VStack(alignment: .leading, spacing: 32) {
                        episodesLogo(for: loaded)

                        EpisodesSectionView(
                            model: seriesModel,
                            seriesId: seriesId(for: loaded.item),
                            ageRating: loaded.item.ageRating,
                            progressStore: coordinator?.progressStore,
                            focus: $focus,
                            onPlay: { playEpisode($0, item: loaded.item) },
                            onRetry: { Task { await loadSeries() } }
                        )
                        .padding(.bottom, 60)
                    }
                    .frame(width: size.width, alignment: .leading)
                    .frame(minHeight: size.height, alignment: .top)
                    .id(ScrollAnchor.episodes)
                }
            }
            .onChange(of: focus) { oldValue, value in
                guard let value else { return }
                if isOverlayFocus(value) {
                    withAnimation { proxy.scrollTo(ScrollAnchor.top, anchor: .top) }
                } else if isOverlayFocus(oldValue ?? .carousel) {
                    withAnimation { proxy.scrollTo(ScrollAnchor.episodes, anchor: .top) }
                }
            }
        }
    }

    private func episodesLogo(for loaded: Loaded) -> some View {
        Group {
            if let logo = loaded.logo {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480, maxHeight: 130)
            } else {
                Text(loaded.item.title)
                    .font(Theme.Font.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private func isOverlayFocus(_ focus: WindowFocus) -> Bool {
        switch focus {
        case .play, .mode, .add, .info, .details, .carousel:
            true
        case .season, .episode, .special:
            false
        }
    }

    private var isEpisodesFocus: Bool {
        switch focus {
        case .season, .episode, .special:
            true
        default:
            false
        }
    }

    private var overlayReturnFocus: WindowFocus {
        guard let item = loaded?.item, isPlayEnabled(for: item) else { return .details }
        return .play
    }

    private var playbackAlertPresented: Binding<Bool> {
        Binding(
            get: {
                if case .some(.failed) = coordinator?.state { return true }
                return false
            },
            set: { presented in
                if !presented { coordinator?.dismissError() }
            }
        )
    }

    private var playbackErrorMessage: String? {
        if case .some(.failed(let error)) = coordinator?.state { return error.message }
        return nil
    }

    private func isSeriesLike(_ item: MediaItem) -> Bool {
        item.kind == .series || item.isAnime
    }

    private func seriesId(for item: MediaItem) -> String {
        PlaybackProgressStore.seriesKey(for: item) ?? item.contentId ?? ""
    }

    private func resumeEntry(for item: MediaItem) -> ResumeEntry? {
        coordinator?.progressStore.entries.first { $0.contentId == seriesId(for: item) }
    }

    private func episodeFromEntry(for item: MediaItem) -> EpisodeItem? {
        guard let entry = resumeEntry(for: item), let videoId = entry.videoId else { return nil }
        return EpisodeItem(
            videoId: videoId,
            season: entry.season ?? 1,
            episode: entry.episode ?? 1,
            title: entry.episodeTitle ?? item.title,
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: entry.runtimeMinutes,
            isReleased: true
        )
    }

    private func playLabel(for item: MediaItem) -> String {
        if item.kind == .movie, let coordinator,
           case .externalService(let service) = coordinator.route(for: item) {
            return service.playCTA
        }
        guard isSeriesLike(item) else { return "Reproduzir" }
        switch seriesModel.phase {
        case .loaded:
            return seriesModel.playLabel(store: coordinator?.progressStore, seriesId: seriesId(for: item))
        case .idle, .loading, .failed:
            if let entry = resumeEntry(for: item), entry.videoId != nil, let code = entry.episodeCode {
                return entry.positionSeconds > 0 ? "Continuar \(code)" : "Reproduzir \(code)"
            }
            return "Reproduzir"
        case .unavailable:
            return "Reproduzir"
        }
    }

    private func isPlayEnabled(for item: MediaItem) -> Bool {
        guard isSeriesLike(item) else { return true }
        switch seriesModel.phase {
        case .loaded:
            if seriesModel.nextEpisode(store: coordinator?.progressStore, seriesId: seriesId(for: item)) != nil {
                return true
            }
            return item.kind == .series && !item.isAnime
                && seriesModel.detail?.behaviorHints?.defaultVideoId != nil
        case .unavailable:
            return true
        case .idle, .loading, .failed:
            return episodeFromEntry(for: item) != nil
        }
    }

    private func showsModeSelector(for item: MediaItem) -> Bool {
        guard !item.isAnime, item.kind == .movie || item.kind == .series,
              let coordinator else { return false }
        return coordinator.route(for: item) == .infuse
    }

    private func play(_ item: MediaItem) {
        guard let coordinator else { return }
        switch resolvePlayTarget(for: item) {
        case .target(let target):
            start(target, item: item, coordinator: coordinator, preferredStream: nil)
        case .blocked(let error):
            coordinator.fail(error)
        case .pending:
            break
        }
    }

    private func playEpisode(_ episode: EpisodeItem, item: MediaItem) {
        guard let coordinator else { return }
        let next = seriesModel.episodeAfter(episode)
        Task { await coordinator.play(item: item, episode: episode, next: next, mode: playbackMode) }
    }

    private func start(
        _ target: PlayTarget,
        item: MediaItem,
        coordinator: PlaybackCoordinator,
        preferredStream: AddonStream?
    ) {
        switch target {
        case .movie:
            Task { await coordinator.play(item: item, mode: playbackMode, preferredStream: preferredStream) }
        case .episode(let episode, let next):
            Task {
                await coordinator.play(
                    item: item,
                    episode: episode,
                    next: next,
                    mode: playbackMode,
                    preferredStream: preferredStream
                )
            }
        }
    }

    private func resolvePlayTarget(for item: MediaItem) -> PlayResolution {
        guard isSeriesLike(item) else { return .target(.movie) }
        switch seriesModel.phase {
        case .loaded:
            if let next = seriesModel.nextEpisode(store: coordinator?.progressStore, seriesId: seriesId(for: item)) {
                return .target(.episode(next, next: seriesModel.episodeAfter(next)))
            }
            if item.kind == .series, !item.isAnime {
                return fallbackTarget(for: item)
            }
            return .blocked(.noEpisodes)
        case .unavailable:
            if item.kind == .series, !item.isAnime {
                return fallbackTarget(for: item)
            }
            return .target(.movie)
        case .idle, .loading, .failed:
            guard let episode = episodeFromEntry(for: item) else { return .pending }
            return .target(.episode(episode, next: nil))
        }
    }

    private func fallbackTarget(for item: MediaItem) -> PlayResolution {
        guard let defaultId = seriesModel.detail?.behaviorHints?.defaultVideoId else {
            return .blocked(.noEpisodes)
        }
        let episode = EpisodeItem(
            videoId: defaultId,
            season: 1,
            episode: 1,
            title: item.title,
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: RuntimeParser.minutes(from: item.runtime),
            isReleased: true
        )
        return .target(.episode(episode, next: nil))
    }

    private func holdMode(_ item: MediaItem) {
        guard playbackMode.isAvailable, !isPlayLoading, !showsSources else { return }
        guard case .target(let target) = resolvePlayTarget(for: item) else { return }
        sourcesTarget = target
        withAnimation(.easeOut(duration: 0.3)) { showsSources = true }
    }

    private func loadSources(
        for target: PlayTarget,
        item: MediaItem
    ) async -> Result<[AddonStream], PlaybackCoordinator.PlaybackError> {
        guard let coordinator else { return .failure(.notConfigured) }
        switch target {
        case .movie:
            return await coordinator.sources(for: item, mode: playbackMode)
        case .episode(let episode, _):
            return await coordinator.sources(videoId: episode.videoId, isAnime: item.isAnime, mode: playbackMode)
        }
    }

    private func selectSource(_ stream: AddonStream, item: MediaItem) {
        withAnimation(.easeOut(duration: 0.3)) { showsSources = false }
        focus = .mode
        guard let coordinator, let target = sourcesTarget else { return }
        sourcesTarget = nil
        start(target, item: item, coordinator: coordinator, preferredStream: stream)
    }

    private func enterFullscreen() {
        guard !isFullscreen, loaded != nil else { return }
        withAnimation(.smooth(duration: Self.expandDuration)) { isFullscreen = true }
        focus = overlayReturnFocus
    }

    private func showDetails() {
        withAnimation(.easeOut(duration: 0.3)) { showsInfo = true }
    }

    private func handleBack() {
        if showsSources {
            withAnimation(.easeOut(duration: 0.3)) { showsSources = false }
            sourcesTarget = nil
            focus = .mode
        } else if showsInfo {
            withAnimation(.easeOut(duration: 0.3)) { showsInfo = false }
            focus = .details
        } else if isFullscreen, isEpisodesFocus {
            focus = overlayReturnFocus
        } else if isFullscreen {
            withAnimation(.smooth(duration: Self.expandDuration)) { isFullscreen = false }
            focus = .carousel
        } else {
            dismiss()
        }
    }

    private func loadSeries() async {
        seriesModel = SeriesDetailViewModel()
        let item = row.item(at: centerIndex)
        guard isSeriesLike(item), let metaProvider else { return }
        await seriesModel.load(item: item, provider: metaProvider, store: coordinator?.progressStore)
    }

    /// Mantém só o background visível até o backdrop central e a logo terminarem
    /// de carregar e o carrossel assentar no título; então revela o hero e o
    /// overlay completos de uma vez (sem o "flash" do título em texto sendo
    /// trocado pela logo). Reexecuta a cada troca de título.
    @MainActor
    private func loadAssets() async {
        let index = centerIndex
        let item = row.item(at: index)
        async let backdrop = WindowAssetLoader.image(item.backdropURL)
        async let logo = WindowAssetLoader.image(item.logoURL)
        try? await Task.sleep(for: .seconds(BackdropCarousel.slideDuration))
        let backdropImage = await backdrop
        let logoImage = await logo
        guard !Task.isCancelled, centerIndex == index else { return }
        withAnimation(.easeOut(duration: 0.6)) {
            loaded = Loaded(
                item: item,
                backdrop: backdropImage.map { Image(decorative: $0, scale: 1) },
                logo: logoImage.map { Image(decorative: $0, scale: 1) }
            )
        }
    }
}

/// Camada sobre o backdrop central do carrossel: invisível na window (a imagem
/// visível é a do carrossel, evitando crossfade da foto sobre ela mesma); na
/// expansão para fullscreen a própria cópia da imagem surge e anima junto — o
/// scroll embaixo nunca muda.
private struct HeroCard: View {
    let item: MediaItem
    var backdrop: Image?
    var isFullscreen: Bool

    var body: some View {
        backdropView
            .animation(imageFade) { view in
                view.opacity(isFullscreen ? 1 : 0)
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: topRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: topRadius,
                style: .continuous
            ))
    }

    private var topRadius: CGFloat { isFullscreen ? 0 : Theme.Radius.window }

    private var imageFade: Animation {
        isFullscreen
            ? .easeOut(duration: 0.1)
            : .easeOut(duration: 0.1).delay(MediaWindowView.expandDuration - 0.1)
    }

    @ViewBuilder
    private var backdropView: some View {
        if let backdrop {
            Color.clear
                .overlay {
                    backdrop
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            item.tint ?? Theme.bgElevated
        }
    }
}

private struct Loaded {
    let item: MediaItem
    let backdrop: Image?
    let logo: Image?
}

private enum PlayTarget {
    case movie
    case episode(EpisodeItem, next: EpisodeItem?)
}

private enum PlayResolution {
    case target(PlayTarget)
    case blocked(PlaybackCoordinator.PlaybackError)
    case pending
}

private enum WindowAssetLoader {
    static func image(_ url: URL?) async -> CGImage? {
        guard let url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }
}
