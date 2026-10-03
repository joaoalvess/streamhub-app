import SwiftUI
import Lumen

struct NativePlayerView: View {
    let session: NativePlaybackSession
    let onClose: () -> Void

    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?
    @StateObject private var player = KSVideoPlayer.Coordinator()
    @State private var options: KSOptions

    init(session: NativePlaybackSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        _options = State(initialValue: Self.makeOptions(session: session))
    }

    var body: some View {
        KSVideoPlayerView(
            coordinator: player,
            url: session.videoURL,
            options: options,
            title: session.title,
            onClose: onClose
        )
        .tvPlayerMetadata(makeMetadata())
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            player.isScaleAspectFill = false
            configurePlayer()
        }
        .onReceive(player.timemodel.$currentTime) { coordinator?.updateNativePosition($0) }
        .onReceive(player.timemodel.$totalTime) { total in
            guard total != Self.placeholderTotalTime else { return }
            coordinator?.updateNativeDuration(total)
        }
    }

    private static let placeholderTotalTime = 1

    private static func makeOptions(session: NativePlaybackSession) -> KSOptions {
        let options = KSOptions()
        options.isSourceSwitchEnabled = true
        if let start = session.startSeconds {
            options.startPlayTime = TimeInterval(start)
        }
        return options
    }

    private func configurePlayer() {
        let close = onClose
        player.onPlaybackEnded = { reason in
            guard case .completed = reason else { return }
            close()
        }
    }

    private func makeMetadata() -> TVPlayerMetadata {
        guard let metadata = session.metadata else { return TVPlayerMetadata() }
        return TVPlayerMetadata(
            subtitle: metadata.subtitle,
            seasonNumber: metadata.seasonNumber,
            episodeNumber: metadata.episodeNumber,
            synopsis: metadata.synopsis,
            artworkURL: metadata.artworkURL,
            year: metadata.year,
            genres: metadata.genres,
            runtimeMinutes: metadata.runtimeMinutes,
            ageRatingLabel: metadata.ageRatingLabel,
            ratingLabel: metadata.ratingLabel,
            cast: metadata.cast.map {
                TVPlayerCredit(name: $0.name, role: $0.character, imageURL: $0.photoURL)
            },
            directors: metadata.directors.map {
                TVPlayerCredit(name: $0.name, role: "Direção", imageURL: $0.photoURL)
            }
        )
    }
}
