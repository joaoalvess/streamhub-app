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
    @State private var loaded: Loaded?
    @State private var playbackMode: PlaybackMode = .dubbed
    @FocusState private var focus: WindowFocus?
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?

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

                    WindowInfoOverlay(
                        item: loaded.item,
                        logo: loaded.logo,
                        focus: $focus,
                        playLabel: playLabel(for: loaded.item),
                        isPlayLoading: isPlayLoading,
                        showsModeSelector: showsModeSelector(for: loaded.item),
                        playbackMode: playbackMode,
                        onPlay: { play(loaded.item) },
                        onSelectMode: { playbackMode = $0 },
                        onShowDetails: showDetails
                    )
                    .frame(width: isFullscreen ? geo.size.width : geo.size.width * 0.9)
                    .allowsHitTesting(isFullscreen)
                    .disabled(showsInfo)
                    .transition(.opacity.combined(with: .offset(y: 16)))

                    if showsInfo {
                        InfoModalView(item: loaded.item)
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
        .alert("Não foi possível reproduzir", isPresented: playbackAlertPresented) {
            Button("OK", role: .cancel) { coordinator?.dismissError() }
        } message: {
            Text(playbackErrorMessage ?? "")
        }
    }

    private var isPlayLoading: Bool {
        coordinator?.state == .loading
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

    private func playLabel(for item: MediaItem) -> String {
        guard item.kind == .movie, let coordinator,
              case .externalService(let service) = coordinator.route(for: item) else {
            return "Reproduzir"
        }
        return service.playCTA
    }

    private func showsModeSelector(for item: MediaItem) -> Bool {
        guard item.kind == .movie, let coordinator else { return false }
        return coordinator.route(for: item) == .infuse
    }

    private func play(_ item: MediaItem) {
        guard let coordinator else { return }
        Task { await coordinator.play(item: item, mode: playbackMode) }
    }

    private func enterFullscreen() {
        guard !isFullscreen, loaded != nil else { return }
        withAnimation(.smooth(duration: Self.expandDuration)) { isFullscreen = true }
        focus = .play
    }

    private func showDetails() {
        withAnimation(.easeOut(duration: 0.3)) { showsInfo = true }
    }

    private func handleBack() {
        if showsInfo {
            withAnimation(.easeOut(duration: 0.3)) { showsInfo = false }
            focus = .details
        } else if isFullscreen {
            withAnimation(.smooth(duration: Self.expandDuration)) { isFullscreen = false }
            focus = .carousel
        } else {
            dismiss()
        }
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

private enum WindowAssetLoader {
    static func image(_ url: URL?) async -> CGImage? {
        guard let url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }
}
