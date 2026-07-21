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

    var body: some View {
        poster
            .frame(width: Theme.Size.posterWidth, height: Theme.Size.posterHeight)
            .overlay { Theme.genreScrim.opacity(isFocused && entry.posterURL != nil ? 1 : 0) }
            .overlay(alignment: .bottom) { footer }
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .hoverEffect(.highlight)
    }

    private var poster: some View {
        AsyncImage(url: entry.posterURL, transaction: Transaction(animation: .default)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .failure:
                placeholder
            case .empty:
                if entry.posterURL == nil {
                    placeholder
                } else {
                    ZStack {
                        Theme.bgElevated
                        ProgressView()
                    }
                }
            @unknown default:
                placeholder
            }
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

    private var footer: some View {
        VStack(spacing: 10) {
            if entry.posterURL != nil {
                Text(entry.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
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
