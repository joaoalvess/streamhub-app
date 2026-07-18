import SwiftUI

struct EpisodeCardView: View {
    enum Style { case episode, special }

    let episode: EpisodeItem
    let progress: Double?
    let isWatched: Bool
    let style: Style
    let ageRating: MediaItem.AgeRating?
    let isFocused: Bool
    var onSelect: () -> Void

    private static let dateLocale = Locale(identifier: "pt_BR")

    var body: some View {
        Button(action: episode.isReleased ? onSelect : {}) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnailComposite
                caption
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .opacity(isFocused ? 1 : 0)
            }
            .scaleEffect(isFocused ? 1.05 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(EpisodeCardButtonStyle())
        .frame(width: Theme.Size.episodeCardWidth)
        .opacity(episode.isReleased ? 1 : 0.5)
    }

    private var thumbnailComposite: some View {
        ZStack {
            thumbnail
                .frame(width: Theme.Size.episodeCardWidth, height: Theme.Size.episodeCardHeight)

            if durationLabel != nil || showsProgress {
                Theme.genreScrim
            }

            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                if let durationLabel {
                    HStack(spacing: 6) {
                        if let durationIcon {
                            Image(systemName: durationIcon)
                        }
                        Text(durationLabel)
                    }
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.leading, 14)
                    .padding(.bottom, showsProgress ? 0 : 14)
                }

                if showsProgress, let progress {
                    MediaProgressBar(progress: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Theme.Size.episodeCardWidth, height: Theme.Size.episodeCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = episode.thumbnailURL {
            AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.bgElevated
            Text("\(episode.episode)")
                .font(.system(size: 72, weight: .heavy))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var caption: some View {
        Group {
            switch style {
            case .episode:
                episodeCaption
            case .special:
                Text(episode.title)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Theme.Size.episodeCardWidth, alignment: .leading)
    }

    private var episodeCaption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EPISÓDIO \(episode.episode)")
                .font(.system(size: 20, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Text(episode.title)
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(episode.overview ?? "")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(5, reservesSpace: true)

            if dateLabel != nil || ageRating != nil {
                HStack(spacing: 10) {
                    if let dateLabel {
                        Text(dateLabel)
                            .font(Theme.Font.meta)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if let ageRating {
                        AgeRatingBadge(rating: ageRating)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var showsProgress: Bool {
        progress != nil && episode.isReleased
    }

    private var durationIcon: String? {
        if isWatched { return "arrow.counterclockwise" }
        return style == .special ? "play.fill" : nil
    }

    private var durationLabel: String? {
        guard episode.isReleased else { return nil }
        return episode.runtimeMinutes.map { "\($0) min" }
    }

    private var dateLabel: String? {
        if !episode.isReleased {
            guard let date = episode.releasedAt else { return "Em breve" }
            return "Estreia em \(date.formatted(.dateTime.day().month(.wide).locale(Self.dateLocale)))"
        }
        return episode.releasedAt.map {
            $0.formatted(.dateTime.day().month(.abbreviated).year().locale(Self.dateLocale))
        }
    }
}

private struct EpisodeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
