import SwiftUI
import Lumen

struct NativePlayerView: View {
    let session: NativePlaybackSession
    let onClose: () -> Void

    @Environment(PlaybackCoordinator.self) private var coordinator: PlaybackCoordinator?
    @StateObject private var player = KSVideoPlayer.Coordinator()

    var body: some View {
        KSVideoPlayerView(
            coordinator: player,
            url: session.videoURL,
            options: makeOptions(),
            title: session.title,
            onClose: onClose
        )
        .tvPlayerMetadata(makeMetadata())
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            player.isScaleAspectFill = false
        }
        .onReceive(player.timemodel.$currentTime) { coordinator?.updateNativePosition($0) }
    }

    private func makeOptions() -> KSOptions {
        let options = KSOptions()
        if let start = session.startSeconds {
            options.startPlayTime = TimeInterval(start)
        }
        return options
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
