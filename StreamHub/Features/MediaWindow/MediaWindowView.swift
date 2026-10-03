import SwiftUI

/// Tela intermediária ao selecionar um título. Apresenta um carrossel de
/// backdrops (window) que expande para fullscreen ao pressionar cima/baixo ou
/// o botão central. Voltar: ficha completa → fullscreen → window → home.
struct MediaWindowView: View {
    static let expandDuration: TimeInterval = 0.55
    private static let seriesDebounce: Duration = .milliseconds(350)
    private static let qualityDebounce: Duration = .milliseconds(600)

    let row: CatalogRow
    let startIndex: Int

    @State private var centerIndex: Int
    @State private var hasLeftStart = false
    @State private var autoplayPending: Bool
    @State private var isFullscreen = false
    @State private var showsInfo = false
    @State private var showsSources = false
    @State private var sourcesTarget: PlayTarget?
    @State private var loaded: LoadedWindow?
    @State private var playbackMode: PlaybackMode = .dubbed
    @State private var playerEngine: PlayerEngine = .stored()
    @State private var seriesModel = SeriesDetailViewModel()
    @State private var qualityResult: QualityResult?
    @FocusState private var focus: WindowFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?
    @Environment(MetaProvider.self) private var metaProvider: MetaProvider?
    @Environment(MyListStore.self) private var myList: MyListStore?
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    private enum ScrollAnchor: Hashable { case top, episodes }

    init(row: CatalogRow, startIndex: Int, autoplay: Bool = false) {
        self.row = row
        self.startIndex = startIndex
        _centerIndex = State(initialValue: max(0, startIndex))
        _autoplayPending = State(initialValue: autoplay)
    }

    var body: some View {
        let nativeSession = coordinator?.nativeSession

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
                        InfoModalView(item: loaded.item, qualityBadges: visibleQuality?.badges ?? [])
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
        .onExitCommand {
            guard nativeSession == nil else { return }
            handleBack()
        }
        .animation(.smooth(duration: Self.expandDuration), value: isFullscreen)
        .onAppear {
            playbackMode = .stored(profileId: coordinator?.progressStore.activeProfileID)
        }
        .onChange(of: centerIndex) { _, _ in
            hasLeftStart = true
            autoplayPending = false
            withAnimation(.easeOut(duration: 0.25)) { loaded = nil }
        }
        .onChange(of: isAutoplayReady) { _, ready in
            guard ready, autoplayPending, let item = loaded?.item else { return }
            autoplayPending = false
            enterFullscreen()
            if isPlayEnabled(for: item) {
                play(item)
            }
        }
        .task(id: centerIndex) { await loadAssets() }
        .task(id: centerIndex) { await loadSeries(after: isAtInitialTitle ? .zero : Self.seriesDebounce) }
        .task(id: qualityRequest) { await loadQuality() }
        .onDisappear {
            guard let coordinator, coordinator.nativeSession == nil else { return }
            coordinator.invalidatePendingPlay()
        }
        .disabled(nativeSession != nil)
        .accessibilityHidden(nativeSession != nil)
        .overlay {
            if let nativeSession {
                NativePlayerView(
                    session: nativeSession,
                    onClose: { coordinator?.completeNativeSession() }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: nativeSession != nil)
        .onChange(of: nativeSession?.id) { previousID, currentID in
            if previousID != nil, currentID == nil {
                focus = overlayReturnFocus
            }
        }
        .alert("Não foi possível reproduzir", isPresented: playbackAlertPresented) {
            Button("OK", role: .cancel) { coordinator?.dismissError() }
        } message: {
            Text(playbackErrorMessage ?? "")
        }
    }

    private var isPlayLoading: Bool {
        coordinator?.state == .loading
    }

    private var isAutoplayReady: Bool {
        guard let item = loaded?.item else { return false }
        guard PlayPlanner.isSeriesLike(item) else { return true }
        switch seriesModel.phase {
        case .loaded, .unavailable, .failed:
            return true
        case .idle, .loading:
            return false
        }
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

    private func overlayView(for loaded: LoadedWindow) -> some View {
        WindowInfoOverlay(
            item: loaded.item,
            logo: loaded.logo,
            focus: $focus,
            playLabel: playLabel(for: loaded.item),
            isPlayLoading: isPlayLoading,
            isPlayEnabled: isPlayEnabled(for: loaded.item),
            showsModeSelector: showsModeSelector(for: loaded.item),
            playbackMode: playbackMode,
            playerEngine: playerEngine,
            isInMyList: myList?.contains(loaded.item) ?? false,
            qualityBadges: visibleQuality?.badges ?? [],
            onPlay: { play(loaded.item) },
            onCycleMode: {
                guard !showsSources else { return }
                playbackMode = playbackMode.next
                playbackMode.store(profileId: coordinator?.progressStore.activeProfileID)
            },
            onHoldMode: { holdMode(loaded.item) },
            onToggleEngine: {
                guard !showsSources else { return }
                playerEngine = playerEngine.next
                playerEngine.store()
            },
            onAdd: { toggleMyList(loaded.item) },
            onInfo: showDetails,
            onShowDetails: showDetails
        )
    }

    private func episodePages(for loaded: LoadedWindow, size: CGSize) -> some View {
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
                            seriesId: PlayPlanner.seriesId(for: loaded.item),
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

    private func episodesLogo(for loaded: LoadedWindow) -> some View {
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
        case .play, .mode, .engine, .add, .info, .details, .carousel:
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

    private func resumeEntry(for item: MediaItem) -> ResumeEntry? {
        coordinator?.progressStore.entry(forSeries: PlayPlanner.seriesId(for: item))
    }

    private func playContext(for item: MediaItem) -> PlayPlanner.Context {
        guard PlayPlanner.isSeriesLike(item) else { return .movie }
        switch seriesModel.phase {
        case .loaded:
            let next = seriesModel.nextEpisode(store: coordinator?.progressStore, seriesId: PlayPlanner.seriesId(for: item))
            return .loaded(
                next: next,
                nextAfter: next.flatMap { seriesModel.episodeAfter($0) },
                defaultVideoId: seriesModel.detail?.behaviorHints?.defaultVideoId
            )
        case .unavailable:
            return .unavailable(defaultVideoId: seriesModel.detail?.behaviorHints?.defaultVideoId)
        case .idle, .loading, .failed:
            return .pending(resume: resumeEntry(for: item))
        }
    }

    private func playLabel(for item: MediaItem) -> String {
        if item.kind == .movie, let coordinator,
           case .externalService(let service) = coordinator.route(for: item) {
            return service.playCTA
        }
        guard PlayPlanner.isSeriesLike(item) else { return "Reproduzir" }
        switch seriesModel.phase {
        case .loaded:
            return seriesModel.playLabel(store: coordinator?.progressStore, seriesId: PlayPlanner.seriesId(for: item))
        case .idle, .loading, .failed:
            return PlayPlanner.resumeLabel(for: resumeEntry(for: item))
        case .unavailable:
            return "Reproduzir"
        }
    }

    private func isPlayEnabled(for item: MediaItem) -> Bool {
        PlayPlanner.isPlayEnabled(for: item, in: playContext(for: item))
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
        let timeline = seriesModel.episodeTimeline
        Task {
            await coordinator.play(
                item: item,
                episode: episode,
                next: next,
                timeline: timeline,
                mode: playbackMode,
                engine: playerEngine
            )
        }
    }

    private func start(
        _ target: PlayTarget,
        item: MediaItem,
        coordinator: PlaybackCoordinator,
        preferredStream: AddonStream?
    ) {
        switch target {
        case .movie:
            Task {
                await coordinator.play(
                    item: item,
                    mode: playbackMode,
                    engine: playerEngine,
                    preferredStream: preferredStream
                )
            }
        case .episode(let episode, let next):
            let timeline = seriesModel.episodeTimeline
            Task {
                await coordinator.play(
                    item: item,
                    episode: episode,
                    next: next,
                    timeline: timeline,
                    mode: playbackMode,
                    engine: playerEngine,
                    preferredStream: preferredStream
                )
            }
        }
    }

    private func resolvePlayTarget(for item: MediaItem) -> PlayResolution {
        PlayPlanner.resolveTarget(for: item, in: playContext(for: item))
    }

    private func toggleMyList(_ item: MediaItem) {
        guard let myList else { return }
        let wasInList = myList.contains(item)
        myList.toggle(item)
        toasts?.show(
            wasInList ? "Removido da Minha lista" : "Adicionado à Minha lista",
            systemImage: wasInList ? "xmark" : "checkmark"
        )
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

    private var qualityRequest: QualityRequest? {
        guard isFullscreen, let coordinator, let item = loaded?.item,
              case .target(let target) = resolvePlayTarget(for: item) else { return nil }
        if case .movie = target, coordinator.route(for: item) != .infuse {
            return nil
        }
        return QualityRequest(item: item, mode: playbackMode, target: target)
    }

    private var visibleQuality: MediaQuality? {
        guard let qualityResult, qualityResult.request == qualityRequest else { return nil }
        return qualityResult.quality
    }

    private func loadQuality() async {
        qualityResult = nil
        guard let request = qualityRequest else { return }
        try? await Task.sleep(for: Self.qualityDebounce)
        guard !Task.isCancelled else { return }
        let result = await loadSources(for: request.target, item: request.item)
        guard !Task.isCancelled, qualityRequest == request,
              case .success(let streams) = result,
              let stream = streams.first(where: \.isPlayable) else { return }
        qualityResult = QualityResult(request: request, quality: StreamQualityParser.parse(stream))
    }

    private func selectSource(_ stream: AddonStream, item: MediaItem) {
        withAnimation(.easeOut(duration: 0.3)) { showsSources = false }
        focus = .mode
        guard let coordinator, let target = sourcesTarget else { return }
        sourcesTarget = nil
        if let contentKey = PlayPlanner.contentKey(for: target, item: item),
           coordinator.nativeSession?.contentKey == contentKey,
           let videoURL = stream.playbackURL {
            coordinator.switchNativeSource(videoURL: videoURL, stream: stream)
            return
        }
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

    private var isAtInitialTitle: Bool {
        !hasLeftStart && centerIndex == max(0, startIndex)
    }

    private var assetsSettleDelay: TimeInterval {
        guard isAtInitialTitle else { return BackdropCarousel.settleDuration }
        return autoplayPending ? BackdropCarousel.slideDuration : 0
    }

    private func loadSeries(after delay: Duration = .zero) async {
        seriesModel = SeriesDetailViewModel()
        let item = row.item(at: centerIndex)
        guard PlayPlanner.isSeriesLike(item), let metaProvider else { return }
        if delay > .zero {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
        }
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
        let settleDelay = assetsSettleDelay
        async let backdrop = Self.image(item.backdropURL, maxPixelSize: ImageSize.backdrop)
        async let logo = Self.image(item.logoURL, maxPixelSize: ImageSize.logo)
        if settleDelay > 0 {
            try? await Task.sleep(for: .seconds(settleDelay))
        }
        let backdropImage = await backdrop
        let logoImage = await logo
        guard !Task.isCancelled, centerIndex == index else { return }
        withAnimation(.easeOut(duration: 0.6)) {
            loaded = LoadedWindow(
                item: item,
                backdrop: backdropImage.map { Image(decorative: $0, scale: 1) },
                logo: logoImage.map { Image(decorative: $0, scale: 1) }
            )
        }
    }

    private static func image(_ url: URL?, maxPixelSize: Int) async -> CGImage? {
        guard let url else { return nil }
        if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            return cached
        }
        return await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
    }
}

private nonisolated struct QualityResult {
    let request: QualityRequest
    let quality: MediaQuality
}

private nonisolated struct QualityRequest: Equatable {
    let item: MediaItem
    let mode: PlaybackMode
    let target: PlayTarget

    static func == (lhs: QualityRequest, rhs: QualityRequest) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.mode == rhs.mode
            && PlayPlanner.contentKey(for: lhs.target, item: lhs.item) == PlayPlanner.contentKey(for: rhs.target, item: rhs.item)
    }
}
