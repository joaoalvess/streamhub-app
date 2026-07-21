import SwiftUI

struct LibraryView: View {
    @State private var model = LibraryViewModel()
    @State private var activeSessionID: UUID?
    @State private var playbackMessage: String?
    @State private var reporter: JellyfinPlaybackReporter?
    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
        .task { await model.loadIfNeeded() }
        .fullScreenCover(item: sessionTarget) { session in
            NativePlayerView(session: session) {
                closePlayer()
            }
        }
        .alert("Não foi possível reproduzir", isPresented: playbackAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackMessage ?? "")
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

    private var sessionTarget: Binding<NativePlaybackSession?> {
        Binding(
            get: {
                guard let session = coordinator?.nativeSession, session.id == activeSessionID else {
                    return nil
                }
                return session
            },
            set: { newValue in
                if newValue == nil {
                    closePlayer()
                }
            }
        )
    }

    private var playbackAlertPresented: Binding<Bool> {
        Binding(
            get: { playbackMessage != nil },
            set: { presented in
                if !presented {
                    playbackMessage = nil
                }
            }
        )
    }

    private func play(_ entry: LibraryEntry) {
        guard let coordinator else { return }
        Task {
            do {
                let url = try await model.streamURL(for: entry)
                coordinator.startNativeSession(
                    videoURL: url,
                    title: entry.name,
                    position: entry.startSeconds,
                    entry: nil,
                    metadata: entry.sessionMetadata()
                )
                activeSessionID = coordinator.nativeSession?.id
                let sessionReporter = model.makeReporter(coordinator: coordinator)
                sessionReporter.start(itemId: entry.id, positionSeconds: entry.startSeconds ?? 0)
                reporter = sessionReporter
            } catch {
                playbackMessage = LibraryViewModel.message(for: error)
            }
        }
    }

    private func closePlayer() {
        guard activeSessionID != nil else { return }
        activeSessionID = nil
        reporter?.stop()
        reporter = nil
        coordinator?.completeNativeSession()
        Task {
            try? await Task.sleep(for: .seconds(1))
            await model.refreshResume()
        }
    }
}
