import SwiftUI

/// Carrossel horizontal de backdrops com "peek" dos títulos vizinhos, sempre em
/// modo window — a expansão para fullscreen acontece no hero da MediaWindow,
/// por cima. É um alvo de foco ÚNICO: esquerda/direita troca de título (snap
/// dirigido por `centerIndex`); cima/baixo ou clique central pede a expansão.
/// A navegação infinita reutiliza o prefetch/reciclagem do `CatalogRow`.
struct BackdropCarousel: View {
    static let slideDuration: TimeInterval = 0.7

    let row: CatalogRow
    @Binding var centerIndex: Int
    var isFullscreen: Bool
    var focus: FocusState<WindowFocus?>.Binding
    var onExpand: () -> Void

    @State private var scrollTarget: Int?

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * 0.9

            Button(action: onExpand) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 28) {
                        ForEach(0..<row.displayCount, id: \.self) { index in
                            BackdropCard(
                                item: row.item(at: index),
                                isCenter: index == centerIndex
                            )
                            .frame(width: cardWidth, height: geo.size.height)
                            .id(index)
                            .onAppear { row.onCardAppear(index) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (geo.size.width - cardWidth) / 2, for: .scrollContent)
                .scrollPosition(id: $scrollTarget, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
                .scrollDisabled(true)
            }
            .buttonStyle(CarouselButtonStyle())
            .focusEffectDisabled()
            .focused(focus, equals: .carousel)
            .disabled(isFullscreen)
            .onMoveCommand { direction in
                switch direction {
                case .left: step(-1)
                case .right: step(1)
                case .up, .down: onExpand()
                default: break
                }
            }
            .animation(.smooth(duration: Self.slideDuration), value: centerIndex)
            .onAppear { if scrollTarget == nil { scrollTarget = centerIndex } }
            .onChange(of: centerIndex) { _, value in
                withAnimation(.smooth(duration: Self.slideDuration)) { scrollTarget = value }
            }
        }
    }

    private func step(_ delta: Int) {
        let next = centerIndex + delta
        guard next >= 0, next < row.displayCount else { return }
        row.onCardAppear(next)
        centerIndex = next
    }
}

/// Estilo neutro: o carrossel já gerencia o próprio visual (card central · peek),
/// então o botão só repassa o conteúdo, sem fundo nem efeito de pressionar.
private struct CarouselButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
