import Foundation

@MainActor
final class JellyfinPlaybackReporter {
    private let sender: @Sendable (JellyfinPlaybackEvent, JellyfinPlaybackReport) async -> Void
    private let positionProvider: @MainActor () -> Int?
    private let progressInterval: Duration
    private let playSessionId = UUID().uuidString
    private var itemId: String?
    private var lastPositionSeconds: Int?
    private var progressTask: Task<Void, Never>?

    init(
        sender: @escaping @Sendable (JellyfinPlaybackEvent, JellyfinPlaybackReport) async -> Void,
        positionProvider: @escaping @MainActor () -> Int?,
        progressInterval: Duration = .seconds(10)
    ) {
        self.sender = sender
        self.positionProvider = positionProvider
        self.progressInterval = progressInterval
    }

    convenience init(api: JellyfinAPI, coordinator: PlaybackCoordinator) {
        self.init(
            sender: { event, body in
                _ = try? await api.report(event, body: body)
            },
            positionProvider: { [weak coordinator] in
                coordinator?.nativePositionSeconds
            }
        )
    }

    func start(itemId: String, positionSeconds: Int) {
        self.itemId = itemId
        lastPositionSeconds = positionSeconds > 0 ? positionSeconds : nil
        let sender = self.sender
        let sessionId = playSessionId
        Task {
            await sender(.start, JellyfinPlaybackReport(
                itemId: itemId,
                playSessionId: sessionId,
                positionSeconds: positionSeconds
            ))
        }
        let interval = progressInterval
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                guard let position = self.positionProvider(), position > 0 else { continue }
                self.lastPositionSeconds = position
                await sender(.progress, JellyfinPlaybackReport(
                    itemId: itemId,
                    playSessionId: sessionId,
                    positionSeconds: position
                ))
            }
        }
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        guard let itemId else { return }
        self.itemId = nil
        let finalPosition = positionProvider() ?? lastPositionSeconds
        guard let finalPosition, finalPosition > 0 else { return }
        let sender = self.sender
        let sessionId = playSessionId
        Task {
            await sender(.stopped, JellyfinPlaybackReport(
                itemId: itemId,
                playSessionId: sessionId,
                positionSeconds: finalPosition,
                isPaused: nil
            ))
        }
    }
}
