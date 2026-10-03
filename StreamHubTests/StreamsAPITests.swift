import Foundation
import Testing
@testable import StreamHub

struct StreamsAPITests {

    @Test func decodesRealStreamWithBehaviorHints() throws {
        let json = Data("""
        {"streams":[{
            "name":"[TB+] StremThru Torz 2160p",
            "description":"Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv\\n💾6.74 GiB 👤5 \\n🇵🇹 / 🇬🇧 Subs / 🇧🇷 / 🇬🇧",
            "url":"https://stremthru.example.xyz/stremio/torz/abc/strem/tt0111161/tb/445bd77/0/file.mkv",
            "behaviorHints":{
                "bingeGroup":"com.aiostreams.viren070|torbox|false|2160p|BluRay|HEVC|DD|Portuguese|English|andrehsa",
                "videoHash":"bfdf5ef09715605d",
                "videoSize":7237543248,
                "filename":"Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv"
            }
        }]}
        """.utf8)
        let response = try JSONDecoder().decode(StreamsResponse.self, from: json)
        let stream = try #require(response.streams.first)
        #expect(stream.isPlayable)
        #expect(stream.behaviorHints?.videoSize == 7_237_543_248)
        #expect(stream.behaviorHints?.filename?.hasSuffix(".mkv") == true)
    }

    @Test func scrapeSummaryIsNotPlayable() throws {
        let json = Data("""
        {"streams":[{
            "name":"🟢 [Torrentio TB] Scrape Summary",
            "description":"✔ Status      : SUCCESS\\n📦 Streams    : 157",
            "externalUrl":"https://github.com/Viren070/AIOStreams",
            "streamData":{"type":"statistic"}
        }]}
        """.utf8)
        let response = try JSONDecoder().decode(StreamsResponse.self, from: json)
        let stream = try #require(response.streams.first)
        #expect(!stream.isPlayable)
        #expect(stream.url == nil)
    }

    @Test func toleratesUnexpectedBehaviorHintShapes() throws {
        let json = Data("""
        {"streams":[{
            "name":"[TB+] Comet 1080p",
            "url":"https://comet.example/resolve/file.mkv",
            "behaviorHints":{"videoSize":123.9,"bingeGroup":null},
            "streamData":{"type":123}
        }]}
        """.utf8)
        let response = try JSONDecoder().decode(StreamsResponse.self, from: json)
        let stream = try #require(response.streams.first)
        #expect(stream.isPlayable)
        #expect(stream.behaviorHints?.videoSize == 123)
        #expect(stream.streamData?.type == nil)
    }

    @Test func nonHTTPStreamIsNotPlayable() throws {
        let json = Data(#"{"streams":[{"name":"magnet","url":"magnet:?xt=urn:btih:abc"}]}"#.utf8)
        let response = try JSONDecoder().decode(StreamsResponse.self, from: json)
        let stream = try #require(response.streams.first)
        #expect(!stream.isPlayable)
    }

    @Test func firstPlayableStreamSkipsStatisticEntries() throws {
        let json = Data("""
        {"streams":[
            {"name":"🟢 Scrape Summary","externalUrl":"https://example.com/summary","streamData":{"type":"statistic"}},
            {"name":"[TB+] Perfil 2160p","url":"https://cdn.example/primeiro.mkv"},
            {"name":"[TB+] Perfil 1080p","url":"https://cdn.example/segundo.mkv"}
        ]}
        """.utf8)
        let response = try JSONDecoder().decode(StreamsResponse.self, from: json)
        let chosen = try #require(response.streams.first { $0.isPlayable })
        #expect(chosen.playbackURL?.absoluteString == "https://cdn.example/primeiro.mkv")
    }

    @Test func gateDelaysCallsBeyondWindowLimit() async throws {
        let gate = RequestGate(limit: 2, window: .milliseconds(250))
        let clock = ContinuousClock()
        let start = clock.now
        try await gate.admit()
        try await gate.admit()
        try await gate.admit()
        let elapsed = clock.now - start
        #expect(elapsed >= .milliseconds(240))
    }

    @Test func gateAllowsCallsWithinLimitImmediately() async throws {
        let gate = RequestGate(limit: 5, window: .seconds(5))
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<5 { try await gate.admit() }
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(1))
    }

    @Test func cancelledWaiterLeavesGateWithoutAdmission() async throws {
        let gate = RequestGate(limit: 1, window: .seconds(60))
        try await gate.admit()
        let waiter = Task { try await gate.admit() }
        waiter.cancel()
        let result = await waiter.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test func retryDelayClampsEpochResetToThirtySeconds() throws {
        let epoch = try rateLimitedResponse(headers: ["ratelimit-reset": "1759500000"])
        #expect(StreamsAPI.retryDelay(from: epoch) == 30)
    }

    @Test func retryDelayKeepsShortValuesAndFloorsNegativeOnes() throws {
        let short = try rateLimitedResponse(headers: ["Retry-After": "2"])
        let negative = try rateLimitedResponse(headers: ["Retry-After": "-5"])
        #expect(StreamsAPI.retryDelay(from: short) == 2)
        #expect(StreamsAPI.retryDelay(from: negative) == 0)
    }

    @Test func retryDelayIgnoresNonNumericHeaders() throws {
        let httpDate = try rateLimitedResponse(headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"])
        let notANumber = try rateLimitedResponse(headers: ["Retry-After": "nan"])
        let missing = try rateLimitedResponse(headers: [:])
        #expect(StreamsAPI.retryDelay(from: httpDate) == nil)
        #expect(StreamsAPI.retryDelay(from: notANumber) == nil)
        #expect(StreamsAPI.retryDelay(from: missing) == nil)
    }

    private func rateLimitedResponse(headers: [String: String]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://streams.example/stream/movie/tt0111161.json"))
        return try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers))
    }
}
