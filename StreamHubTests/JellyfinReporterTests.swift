import Foundation
import Testing
@testable import StreamHub

actor ReportRecorder {
    private(set) var events: [(event: JellyfinPlaybackEvent, body: JellyfinPlaybackReport)] = []

    func record(_ event: JellyfinPlaybackEvent, _ body: JellyfinPlaybackReport) {
        events.append((event, body))
    }
}

@MainActor
struct JellyfinReporterTests {

    private final class PositionHolder {
        var value: Int?

        init(_ value: Int?) {
            self.value = value
        }
    }

    private func waitUntil(
        _ recorder: ReportRecorder,
        satisfies predicate: ([(event: JellyfinPlaybackEvent, body: JellyfinPlaybackReport)]) -> Bool
    ) async -> [(event: JellyfinPlaybackEvent, body: JellyfinPlaybackReport)] {
        for _ in 0..<200 {
            let events = await recorder.events
            if predicate(events) {
                return events
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await recorder.events
    }

    @Test func reportsStartProgressAndStopWithSameSession() async throws {
        let recorder = ReportRecorder()
        let holder = PositionHolder(120)
        let reporter = JellyfinPlaybackReporter(
            sender: { event, body in await recorder.record(event, body) },
            positionProvider: { holder.value },
            progressInterval: .milliseconds(20)
        )
        reporter.start(itemId: "item-1", positionSeconds: 30)
        _ = await waitUntil(recorder) { events in
            events.contains { $0.event == .progress }
        }
        reporter.stop()
        let events = await waitUntil(recorder) { events in
            events.contains { $0.event == .stopped }
        }

        let startEvent = try #require(events.first { $0.event == .start })
        #expect(startEvent.body.itemId == "item-1")
        #expect(startEvent.body.positionTicks == 300_000_000)
        #expect(startEvent.body.playMethod == "DirectPlay")

        let progressEvent = try #require(events.first { $0.event == .progress })
        #expect(progressEvent.body.positionTicks == 1_200_000_000)

        let stopEvent = try #require(events.first { $0.event == .stopped })
        #expect(stopEvent.body.positionTicks == 1_200_000_000)
        #expect(stopEvent.body.isPaused == nil)

        let sessionIds = Set(events.map { $0.body.playSessionId })
        #expect(sessionIds.count == 1)
    }

    @Test func stopWithoutKnownPositionSendsOnlyStart() async {
        let recorder = ReportRecorder()
        let reporter = JellyfinPlaybackReporter(
            sender: { event, body in await recorder.record(event, body) },
            positionProvider: { nil },
            progressInterval: .seconds(60)
        )
        reporter.start(itemId: "item-1", positionSeconds: 0)
        reporter.stop()
        _ = await waitUntil(recorder) { events in
            events.contains { $0.event == .start }
        }
        try? await Task.sleep(for: .milliseconds(50))
        let all = await recorder.events
        #expect(all.contains { $0.event == .start })
        #expect(all.contains { $0.event == .stopped } == false)
    }

    @Test func stopFallsBackToLastKnownPosition() async throws {
        let recorder = ReportRecorder()
        let reporter = JellyfinPlaybackReporter(
            sender: { event, body in await recorder.record(event, body) },
            positionProvider: { nil },
            progressInterval: .seconds(60)
        )
        reporter.start(itemId: "item-1", positionSeconds: 45)
        reporter.stop()
        let events = await waitUntil(recorder) { events in
            events.contains { $0.event == .stopped }
        }
        let stopEvent = try #require(events.first { $0.event == .stopped })
        #expect(stopEvent.body.positionTicks == 450_000_000)
    }

    @Test func secondStopDoesNotSendAgain() async {
        let recorder = ReportRecorder()
        let reporter = JellyfinPlaybackReporter(
            sender: { event, body in await recorder.record(event, body) },
            positionProvider: { 90 },
            progressInterval: .seconds(60)
        )
        reporter.start(itemId: "item-1", positionSeconds: 10)
        reporter.stop()
        reporter.stop()
        _ = await waitUntil(recorder) { events in
            events.contains { $0.event == .stopped }
        }
        try? await Task.sleep(for: .milliseconds(50))
        let all = await recorder.events
        #expect(all.filter { $0.event == .stopped }.count == 1)
    }
}
