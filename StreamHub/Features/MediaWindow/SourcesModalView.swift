import SwiftUI

struct SourcesModalView: View {
    let mode: PlaybackMode
    let loadSources: () async -> Result<[AddonStream], PlaybackCoordinator.PlaybackError>
    let onSelect: (AddonStream) -> Void

    private enum Phase {
        case loading
        case loaded([AddonStream])
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @FocusState private var focusedIndex: Int?

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text("Fontes — \(mode.label)")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                content
            }
            .padding(48)
            .frame(maxWidth: 920, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .focusable(!hasRows)
        .defaultFocus($focusedIndex, 0)
        .onChange(of: hasRows) { _, has in
            if has { focusedIndex = 0 }
        }
        .task {
            switch await loadSources() {
            case .success(let streams):
                phase = .loaded(streams)
            case .failure(let error):
                phase = .failed(error.message)
            }
        }
    }

    private var hasRows: Bool {
        if case .loaded(let streams) = phase { return !streams.isEmpty }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 14) {
                ProgressView()
                    .tint(Theme.textPrimary)
                Text("Buscando fontes…")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .loaded(let streams) where streams.isEmpty:
            Text(PlaybackCoordinator.PlaybackError.noSources.message)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textSecondary)
        case .loaded(let streams):
            ScrollView(.vertical) {
                VStack(spacing: 12) {
                    ForEach(Array(streams.enumerated()), id: \.offset) { index, stream in
                        Button {
                            onSelect(stream)
                        } label: {
                            row(stream, isAutomatic: index == 0)
                        }
                        .buttonStyle(SourceRowStyle(isFocused: focusedIndex == index))
                        .focused($focusedIndex, equals: index)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 680)
        case .failed(let message):
            Text(message)
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func row(_ stream: AddonStream, isAutomatic: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(stream.name ?? "Fonte")
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if isAutomatic {
                    Text("Automática")
                        .font(Theme.Font.badge)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.fillOnDark))
                }
            }
            if let description = stream.description {
                Text(description)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct SourceRowStyle: ButtonStyle {
    var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? Theme.fillOnDark : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
