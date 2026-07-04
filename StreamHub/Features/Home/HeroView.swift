import SwiftUI

enum HeroControl: Hashable {
    case play, add, info, next
}

struct HeroView: View {
    let items: [MediaItem]
    var focusedControl: FocusState<HeroControl?>.Binding? = nil
    var heroTint: Binding<Color>? = nil
    @State private var index = 0

    @Namespace private var heroFocus

    private var current: MediaItem? {
        guard !items.isEmpty, items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func metadataLine(for item: MediaItem) -> String {
        let genres = item.genres.joined(separator: " · ")
        switch item.kind {
        case .series:
            return genres.isEmpty ? "Programa de TV" : "Programa de TV · " + genres
        case .movie, .anime:
            return genres
        }
    }

    @ViewBuilder
    private func metadataRow(for item: MediaItem) -> some View {
        HStack(spacing: 10) {
            if let badge = item.serviceBadge {
                serviceMark(badge)
                Text("·")
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(metadataLine(for: item))
                .foregroundStyle(Theme.textPrimary)
            if let rating = item.ageRating {
                AgeRatingBadge(rating: rating)
            }
        }
        .font(Theme.Font.meta)
    }

    @ViewBuilder
    private func serviceMark(_ badge: String) -> some View {
        if badge == "tv" {
            HStack(spacing: 3) {
                Image(systemName: "apple.logo")
                Text("tv+")
            }
            .foregroundStyle(Theme.textPrimary)
        } else {
            Text(badge)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func advance() {
        guard !items.isEmpty else { return }
        index = (index + 1) % items.count
    }

    var body: some View {
        ZStack(alignment: .leading) {
            backdrop

            Theme.heroGradientVertical
            Theme.heroGradientHorizontal

            if let item = current {
                infoBlock(for: item)
                    .offset(y: 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { pageDots }
        .onAppear { syncTint() }
        .onChange(of: index) { _, _ in syncTint() }
    }

    private func syncTint() {
        heroTint?.wrappedValue = current?.tint ?? Theme.bg
    }

    @ViewBuilder
    private var pageDots: some View {
        if items.count > 1 {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { i in
                    Circle()
                        .fill(Theme.textPrimary.opacity(i == index ? 1 : 0.35))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, Theme.Metrics.heroOverlap - Theme.Metrics.rowSpacing + 5)
            .animation(.easeInOut(duration: 0.2), value: index)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        AsyncImage(url: current?.backdropURL, transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            default:
                ZStack {
                    Theme.bgElevated
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func infoBlock(for item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let logoURL = item.logoURL {
                AsyncImage(url: logoURL, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 520, maxHeight: 200, alignment: .leading)
                            .transition(.opacity)
                    default:
                        ProgressView()
                            .frame(height: 120, alignment: .leading)
                    }
                }
            } else {
                Text(item.title)
                    .font(Theme.Font.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
            }

            metadataRow(for: item)

            Text(item.synopsis)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .frame(maxWidth: 640, alignment: .leading)

            ctaRow(for: item)
                .padding(.top, 8)
        }
        .padding(.leading, Theme.Metrics.edgeH)
        .padding(.trailing, Theme.Metrics.edgeH)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func ctaRow(for item: MediaItem) -> some View {
        HStack(spacing: 24) {
            Button(action: {}) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("Reproduzir")
                }
            }
            .buttonStyle(HeroButtonStyle(shape: .capsule, isActive: isActive(.play)))
            .prefersDefaultFocus(in: heroFocus)
            .heroControlFocus(focusedControl, .play)

            circleButton(symbol: "plus", control: .add, action: {})
            circleButton(symbol: "info.circle", control: .info, action: {})
            circleButton(symbol: "chevron.right", control: .next, action: advance)
        }
        .focusScope(heroFocus)
    }

    private func isActive(_ control: HeroControl) -> Bool {
        focusedControl?.wrappedValue == control
    }

    @ViewBuilder
    private func circleButton(symbol: String, control: HeroControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(HeroButtonStyle(shape: .circle, isActive: isActive(control)))
        .heroControlFocus(focusedControl, control)
    }
}

private extension View {
    @ViewBuilder
    func heroControlFocus(_ binding: FocusState<HeroControl?>.Binding?, _ control: HeroControl) -> some View {
        if let binding {
            focused(binding, equals: control)
        } else {
            self
        }
    }
}

#Preview {
    HeroView(items: [
        MediaItem(
            title: "Servant",
            kind: .series,
            genres: ["Suspense", "Drama"],
            posterURL: nil,
            backdropURL: URL(string: "https://image.tmdb.org/t/p/w1280/7nsRpSCYcDGLcDmFAISHC8zMQ0D.jpg"),
            logoURL: nil,
            synopsis: "No meio de uma disputa conjugal, um casal enlutado encontra uma força sinistra dentro de sua própria casa.",
            year: 2019
        )
    ])
    .frame(height: 700)
    .background(Theme.bg)
}
