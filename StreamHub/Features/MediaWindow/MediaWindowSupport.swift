import SwiftUI

/// Camada sobre o backdrop central do carrossel: invisível na window (a imagem
/// visível é a do carrossel, evitando crossfade da foto sobre ela mesma); na
/// expansão para fullscreen a própria cópia da imagem surge e anima junto — o
/// scroll embaixo nunca muda.
struct HeroCard: View {
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

struct LoadedWindow {
    let item: MediaItem
    let backdrop: Image?
    let logo: Image?
}

nonisolated enum PlayTarget {
    case movie
    case episode(EpisodeItem, next: EpisodeItem?)
}

nonisolated enum PlayResolution {
    case target(PlayTarget)
    case blocked(PlaybackCoordinator.PlaybackError)
    case pending
}
