import SwiftUI

enum WindowFocus: Hashable {
    case carousel
    case details
    case play
    case add
    case info
}

/// Camada fixa sobre o backdrop central: logo, tipo·gênero, sinopse, linha de
/// metadata + selos, botões e elenco·direção. Na window os botões são
/// decorativos (o pai aplica `allowsHitTesting(false)`); no fullscreen eles
/// recebem foco.
struct WindowInfoOverlay: View {
    let item: MediaItem
    var logo: Image?
    var focus: FocusState<WindowFocus?>.Binding
    var onPlay: () -> Void = {}
    var onAdd: () -> Void = {}
    var onInfo: () -> Void = {}
    var onShowDetails: () -> Void = {}

    private let horizontalInset: CGFloat = 64
    private let bottomInset: CGFloat = 106

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            infoBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            CastDirectionView(cast: item.cast, directors: item.directors)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, horizontalInset)
                .padding(.bottom, bottomInset)
        }
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            logoView
            infoPlate
            ctaRow
                .padding(.top, 6)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.leading, horizontalInset)
        .padding(.bottom, bottomInset)
    }

    @ViewBuilder
    private var logoView: some View {
        if let logo {
            logo
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 460, maxHeight: 170, alignment: .leading)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(item.title)
            .font(Theme.Font.heroTitle)
            .foregroundStyle(Theme.textPrimary)
    }

    private var typeGenreRow: some View {
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
    }

    private var infoPlate: some View {
        Button(action: onShowDetails) {
            VStack(alignment: .leading, spacing: 12) {
                typeGenreRow
                synopsis
                metaQualityRow
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PlateButtonStyle())
        .focused(focus, equals: .details)
        .liquidGlassFocusBorder(focus.wrappedValue == .details, cornerRadius: 20)
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var synopsis: some View {
        Text(item.synopsis)
            .font(Theme.Font.meta)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(3)
    }

    private var metaQualityRow: some View {
        HStack(spacing: 14) {
            if !item.yearRuntimeLabel.isEmpty {
                Text(item.yearRuntimeLabel)
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textPrimary)
            }
            QualityBadgesView()
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 24) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("Reproduzir")
                }
            }
            .buttonStyle(HeroButtonStyle(shape: .capsule, isActive: focus.wrappedValue == .play))
            .focused(focus, equals: .play)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(HeroButtonStyle(shape: .circle, isActive: focus.wrappedValue == .add))
            .focused(focus, equals: .add)

            Button(action: onInfo) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(HeroButtonStyle(shape: .circle, isActive: focus.wrappedValue == .info))
            .focused(focus, equals: .info)
        }
    }
}

/// Estilo neutro para a placa de informações: o realce de foco fica por conta
/// do `liquidGlassFocusBorder`, sem o hover branco dos botões de ação.
private struct PlateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension MediaItem {
    var typeGenreLabel: String {
        let typeLabel: String
        switch kind {
        case .movie: typeLabel = "Filme"
        case .series: typeLabel = "Série"
        case .anime: typeLabel = "Anime"
        }
        if let genre = genres.first, !genre.isEmpty {
            return "\(typeLabel) · \(genre)"
        }
        return typeLabel
    }

    var yearRuntimeLabel: String {
        var parts: [String] = []
        if year > 0 { parts.append(String(year)) }
        if let runtime, !runtime.isEmpty { parts.append(runtime) }
        return parts.joined(separator: " · ")
    }

    var castLabel: String? {
        let names = cast.prefix(3).map(\.name)
        guard !names.isEmpty else { return nil }
        return "Estrelando \(names.formatted(.list(type: .and)))"
    }
}
