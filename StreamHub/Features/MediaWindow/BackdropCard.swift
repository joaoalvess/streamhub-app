import SwiftUI

/// O backdrop de um título dentro do carrossel, sempre em modo window: a imagem
/// crua com cantos superiores arredondados — os gradientes de legibilidade vivem
/// no hero da MediaWindow, por cima. Cards laterais (peek) ficam esmaecidos.
/// O estado de carregamento mostra só o fundo, sem chrome.
struct BackdropCard: View {
    let item: MediaItem
    var isCenter: Bool = true

    var body: some View {
        AsyncImage(url: item.backdropURL, transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                Color.clear
                    .overlay {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .transition(.opacity)
            default:
                ZStack {
                    item.tint ?? Theme.bgElevated
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay { peekDim }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Theme.Radius.window,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Theme.Radius.window,
            style: .continuous
        ))
    }

    @ViewBuilder
    private var peekDim: some View {
        if !isCenter {
            Color.black.opacity(0.5)
        }
    }
}
