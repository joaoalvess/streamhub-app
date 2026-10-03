import SwiftUI

struct LibraryRowView: View {
    let title: String
    let entries: [LibraryEntry]
    var onPlay: (LibraryEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.titleGap) {
            Text(title)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, Theme.Metrics.edgeH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Metrics.cardSpacing) {
                    ForEach(entries) { entry in
                        LibraryCardView(entry: entry) {
                            onPlay(entry)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.edgeH)
                .padding(.vertical, Theme.Metrics.focusHeadroom)
            }
            .scrollClipDisabled()
            .focusSection()
        }
    }
}

struct LibraryCardView: View {
    let entry: LibraryEntry
    var onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            LibraryCardLabel(entry: entry)
        }
        .buttonStyle(.borderless)
    }
}

private struct LibraryCardLabel: View {
    let entry: LibraryEntry
    @Environment(\.isFocused) private var isFocused
    @State private var failedPosterURL: URL?

    var body: some View {
        poster
            .frame(width: Theme.Size.posterWidth, height: Theme.Size.posterHeight)
            .overlay { Theme.genreScrim.opacity(isFocused && entry.posterURL != nil ? 1 : 0) }
            .overlay(alignment: .topLeading) { badges }
            .overlay(alignment: .bottom) { footer }
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .hoverEffect(.highlight)
    }

    private var poster: some View {
        RemoteImage(url: entry.posterURL, maxPixelSize: ImageSize.poster) {
            if entry.posterURL == nil || entry.posterURL == failedPosterURL {
                placeholder
            } else {
                Theme.bgElevated
            }
        }
        .task(id: entry.posterURL) {
            guard let url = entry.posterURL,
                  await ImagePipeline.shared.image(for: url, maxPixelSize: ImageSize.poster) == nil else { return }
            failedPosterURL = url
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.bgElevated
            VStack(spacing: 14) {
                Image(systemName: "film")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                Text(entry.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .padding(.horizontal, 20)
        }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            ForEach(entry.quality.compactBadges, id: \.self) { label in
                badge(label)
            }
            if let label = entry.audioLabel {
                badge(label)
            }
        }
        .padding(8)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.badge)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.65), in: Capsule())
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if entry.posterURL != nil {
                Text(entry.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .opacity(isFocused ? 1 : 0)
            }
            if let progress = entry.progress {
                MediaProgressBar(progress: progress)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 6)
    }
}
