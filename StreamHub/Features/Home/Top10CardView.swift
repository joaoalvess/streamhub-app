import SwiftUI

struct Top10CardView: View {
    let rank: Int
    let item: MediaItem
    var onSelect: () -> Void = {}

    var body: some View {
        Button(action: onSelect) {
            PosterCard(item: item, rank: rank)
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    HStack(alignment: .top, spacing: Theme.Metrics.cardSpacing) {
        Top10CardView(
            rank: 1,
            item: MediaItem(
                title: "Seus Amigos Vizinhos",
                kind: .series,
                genres: ["Drama"],
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/q6cYZjQAfvJqGGz0e0HQVwL2zFD.jpg"),
                backdropURL: nil,
                synopsis: "Um psicanalista de Westchester vê a própria vida desmoronar.",
                year: 2024
            )
        )
        Top10CardView(
            rank: 10,
            item: MediaItem(
                title: "For All Mankind",
                kind: .series,
                genres: ["Ficção Científica"],
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/q6cYZjQAfvJqGGz0e0HQVwL2zFD.jpg"),
                backdropURL: nil,
                synopsis: "Uma releitura da corrida espacial.",
                year: 2019
            )
        )
    }
    .padding(Theme.Metrics.focusHeadroom)
    .background(Theme.backgroundGradient)
}
