import Foundation
import Testing
@testable import StreamHub

struct InfuseURLTests {

    private func queryValues(_ url: URL) throws -> [(name: String, value: String?)] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).map { ($0.name, $0.value) }
    }

    private func value(_ name: String, in url: URL) throws -> String? {
        try queryValues(url).first { $0.name == name }?.value
    }

    @Test func buildsPlayURLThatRoundTripsAllParameters() throws {
        let video = try #require(URL(string: "https://cdn.example/dld/abc?token=x&exp=99"))
        let item = InfusePlayItem(videoURL: video, filename: "Inception (2010).mkv", positionSeconds: 845)
        let url = try #require(InfuseURLBuilder.playURL(item: item))

        #expect(url.scheme == "infuse")
        #expect(url.host() == "x-callback-url")
        #expect(url.path() == "/play")
        #expect(try value("url", in: url) == video.absoluteString)
        #expect(try value("position", in: url) == "845")
        #expect(try value("filename", in: url) == "Inception (2010).mkv")
        #expect(try value("x-success", in: url) == "streamhub://infuse/success")
        #expect(try value("x-error", in: url) == "streamhub://infuse/error")
    }

    @Test func videoURLQueryDelimitersDoNotLeakIntoInfuseQuery() throws {
        let video = try #require(URL(string: "https://cdn.example/dld/abc?token=x&exp=99"))
        let item = InfusePlayItem(videoURL: video, filename: nil, positionSeconds: nil)
        let url = try #require(InfuseURLBuilder.playURL(item: item))

        let names = try queryValues(url).map(\.name)
        #expect(names == ["url", "x-success", "x-error"])
    }

    @Test func encodesPlusSignInsideVideoURL() throws {
        let video = try #require(URL(string: "https://cdn.example/file?sig=ab+cd"))
        let item = InfusePlayItem(videoURL: video, filename: nil, positionSeconds: nil)
        let url = try #require(InfuseURLBuilder.playURL(item: item))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.percentEncodedQuery?.contains("%2B") == true)
        #expect(components.percentEncodedQuery?.contains("+") == false)
        #expect(try value("url", in: url) == video.absoluteString)
    }

    @Test func omitsOptionalParameters() throws {
        let video = try #require(URL(string: "https://cdn.example/file.mkv"))
        let item = InfusePlayItem(videoURL: video, filename: nil, positionSeconds: nil)
        let url = try #require(InfuseURLBuilder.playURL(item: item))

        let names = try queryValues(url).map(\.name)
        #expect(!names.contains("position"))
        #expect(!names.contains("filename"))
    }

    @Test func parsesSuccessCallback() throws {
        let url = try #require(URL(
            string: "streamhub://infuse/success?lastPlayedUrl=https%3A%2F%2Fcdn.example%2Ffile.mkv&position=845"
        ))
        let callback = try #require(InfuseCallback(url: url))
        #expect(callback == .success(lastPlayedURL: "https://cdn.example/file.mkv", position: 845))
    }

    @Test func parsesErrorCallbackWithFailedURLs() throws {
        let url = try #require(URL(
            string: "streamhub://infuse/error?errorCode=100&errorMessage=Bad&failedUrl=https%3A%2F%2Fa&failedUrl=https%3A%2F%2Fb"
        ))
        let callback = try #require(InfuseCallback(url: url))
        #expect(callback == .error(code: "100", message: "Bad", failedURLs: ["https://a", "https://b"]))
    }

    @Test func rejectsForeignURLs() throws {
        let wrongScheme = try #require(URL(string: "otherapp://infuse/success?position=1"))
        let wrongHost = try #require(URL(string: "streamhub://other/success?position=1"))
        let wrongPath = try #require(URL(string: "streamhub://infuse/unknown"))
        #expect(InfuseCallback(url: wrongScheme) == nil)
        #expect(InfuseCallback(url: wrongHost) == nil)
        #expect(InfuseCallback(url: wrongPath) == nil)
    }
}
