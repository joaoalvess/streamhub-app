import SwiftUI
import Observation

@Observable @MainActor
final class LibraryPlaybackModel {
    private(set) var activeSessionID: UUID?
    var playbackMessage: String?
    var onSessionEnded: (() -> Void)?

    private let api: JellyfinAPI
    private var reporter: JellyfinPlaybackReporter?

    init(api: JellyfinAPI = JellyfinAPI()) {
        self.api = api
    }

    func play(_ entry: LibraryEntry, coordinator: PlaybackCoordinator?) {
        guard let coordinator else { return }
        Task {
            do {
                let url = try await api.streamURL(itemId: entry.id)
                coordinator.startNativeSession(
                    videoURL: url,
                    title: entry.name,
                    position: entry.startSeconds,
                    entry: nil,
                    metadata: entry.sessionMetadata()
                )
                activeSessionID = coordinator.nativeSession?.id
                let sessionReporter = JellyfinPlaybackReporter(api: api, coordinator: coordinator)
                sessionReporter.start(itemId: entry.id, positionSeconds: entry.startSeconds ?? 0)
                reporter = sessionReporter
            } catch {
                playbackMessage = LibraryViewModel.message(for: error)
            }
        }
    }

    func closePlayer(coordinator: PlaybackCoordinator?) {
        guard activeSessionID != nil else { return }
        activeSessionID = nil
        reporter?.stop()
        reporter = nil
        coordinator?.completeNativeSession()
        onSessionEnded?()
    }

    func session(in coordinator: PlaybackCoordinator?) -> NativePlaybackSession? {
        guard let session = coordinator?.nativeSession, session.id == activeSessionID else {
            return nil
        }
        return session
    }
}

struct LibraryPlaybackPresentation: ViewModifier {
    let playback: LibraryPlaybackModel
    let coordinator: PlaybackCoordinator?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: sessionTarget) { session in
                NativePlayerView(session: session) {
                    playback.closePlayer(coordinator: coordinator)
                }
            }
            .alert("Não foi possível reproduzir", isPresented: alertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(playback.playbackMessage ?? "")
            }
    }

    private var sessionTarget: Binding<NativePlaybackSession?> {
        Binding(
            get: { playback.session(in: coordinator) },
            set: { newValue in
                if newValue == nil {
                    playback.closePlayer(coordinator: coordinator)
                }
            }
        )
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { playback.playbackMessage != nil },
            set: { presented in
                if !presented {
                    playback.playbackMessage = nil
                }
            }
        )
    }
}

extension View {
    func libraryPlayback(_ playback: LibraryPlaybackModel, coordinator: PlaybackCoordinator?) -> some View {
        modifier(LibraryPlaybackPresentation(playback: playback, coordinator: coordinator))
    }
}
