import SwiftUI

struct LibraryView: View {
    @State private var model = LibraryViewModel()
    @State private var playback = LibraryPlaybackModel()
    @State private var showSearch = false
    @State private var showAll = false
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
        .task {
            playback.onSessionEnded = refreshAfterSession
            await model.loadIfNeeded()
        }
        .libraryPlayback(playback, coordinator: coordinator)
        .fullScreenCover(isPresented: $showSearch) {
            LibrarySearchView(onSessionEnded: refreshAfterSession)
        }
        .fullScreenCover(isPresented: $showAll) {
            LibraryAllView(onSessionEnded: refreshAfterSession)
        }
    }

    private func refreshAfterSession() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            await model.refreshResume()
        }
    }

    private var content: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
                switch model.phase {
                case .loading:
                    loadingView
                case .failed(let message):
                    failureView(message)
                case .loaded:
                    actionsHeader
                    if model.rows.isEmpty {
                        emptyView
                    } else {
                        rowsView
                    }
                }
            }
            .padding(.bottom, Theme.Metrics.rowSpacing)
        }
        .scrollClipDisabled()
    }

    private var actionsHeader: some View {
        HStack(spacing: 24) {
            Button {
                showSearch = true
            } label: {
                Label("Buscar", systemImage: "magnifyingglass")
                    .font(Theme.Font.cardTitle)
            }
            Button {
                showAll = true
            } label: {
                Label("Todos os títulos", systemImage: "square.grid.3x3")
                    .font(Theme.Font.cardTitle)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Metrics.edgeH)
        .padding(.top, Theme.Metrics.focusHeadroom)
        .focusSection()
    }

    private var rowsView: some View {
        ForEach(model.rows) { row in
            LibraryRowView(title: row.title, entries: row.entries, onPlay: play)
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 220)
    }

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text("Sua biblioteca está vazia")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("Adicione conteúdo ao Jellyfin para vê-lo aqui.")
                .font(Theme.Font.meta)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Text(message)
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Button("Tentar novamente") {
                Task { await model.load() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 220)
        .focusSection()
    }

    private func play(_ entry: LibraryEntry) {
        playback.play(entry, coordinator: coordinator)
    }
}
