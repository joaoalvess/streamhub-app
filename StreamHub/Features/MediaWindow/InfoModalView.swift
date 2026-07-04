import SwiftUI

/// Ficha completa do título, aberta ao clicar na placa de informações do
/// fullscreen: descrição sem cortes e metadados. Sem ações próprias — o botão
/// voltar fecha (tratado pela MediaWindowView).
struct InfoModalView: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(item.title)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 10) {
                    if let rating = item.ageRating {
                        AgeRatingBadge(rating: rating)
                    }
                    Text(item.typeGenreLabel)
                        .foregroundStyle(Theme.textPrimary)
                    if let imdb = item.imdbRating {
                        ImdbRatingLabel(rating: imdb)
                    }
                }
                .font(Theme.Font.meta)

                Text(item.synopsis)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)

                if let cast = item.castLabel {
                    Text(cast)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }

                HStack(spacing: 14) {
                    if !item.yearRuntimeLabel.isEmpty {
                        Text(item.yearRuntimeLabel)
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    QualityBadgesView()
                }
                .padding(.top, 8)
            }
            .padding(48)
            .frame(maxWidth: 920, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .focusable()
    }
}
