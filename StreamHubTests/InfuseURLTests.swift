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

    @Test func fullyEncodesReservedDelimitersInQueryValues() throws {
        let video = try #require(URL(
            string: "https://comet.example/eyJhIjoiYiJ9/playback/8592abcdef/0/0/n/n?torrent_name=Free.Guy.mkv&name=Free%20Guy&media_id=tt6264654"
        ))
        let item = InfusePlayItem(
            videoURL: video,
            filename: "Free Guy: Assumindo o Controle (2021).mkv",
            positionSeconds: nil
        )
        let url = try #require(InfuseURLBuilder.playURL(item: item))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.percentEncodedQuery)

        #expect(!query.contains("?"))
        #expect(!query.contains(":"))
        #expect(!query.contains("/"))
        #expect(!query.contains("+"))
        let urlValue = try #require(components.percentEncodedQueryItems?.first { $0.name == "url" }?.value)
        #expect(urlValue.hasPrefix("https%3A%2F%2F"))
    }

    @Test func roundTripsCometStyleURLExactly() throws {
        let video = try #require(URL(
            string: "https://comet.feels.legal/eyJkZWJyaWQiOiJ0b3Jib3gifQ%3D%3D/playback/8592abcdef/0/0/n/n?torrent_name=Free%20Guy%202021&name=Free%2520Guy&media_id=tt6264654"
        ))
        let item = InfusePlayItem(videoURL: video, filename: nil, positionSeconds: nil)
        let url = try #require(InfuseURLBuilder.playURL(item: item))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(try value("url", in: url) == video.absoluteString)
        #expect(components.percentEncodedQuery?.contains("%253D") == true)
        #expect(components.percentEncodedQuery?.contains("%2520") == true)
    }

    @Test func encodesFilenameWithColonAndSpaces() throws {
        let video = try #require(URL(string: "https://cdn.example/file.mkv"))
        let filename = "Free Guy: Assumindo o Controle (2021).mkv"
        let item = InfusePlayItem(videoURL: video, filename: filename, positionSeconds: nil)
        let url = try #require(InfuseURLBuilder.playURL(item: item))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.percentEncodedQuery?.contains("Free%20Guy%3A%20Assumindo") == true)
        #expect(try value("filename", in: url) == filename)
    }

    private func episode(season: Int, number: Int) -> EpisodeItem {
        EpisodeItem(
            videoId: "tt5753856:\(season):\(number)",
            season: season,
            episode: number,
            title: "Episódio \(number)",
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: 60,
            isReleased: true
        )
    }

    private func seriesItem(title: String) -> MediaItem {
        MediaItem(
            contentId: "tt5753856",
            imdbId: "tt5753856",
            title: title,
            kind: .series,
            genres: [],
            posterURL: nil,
            backdropURL: nil,
            synopsis: "",
            year: 2017
        )
    }

    @Test func episodeFilenameUsesSeasonEpisodeCodeWithZeroPadding() {
        let filename = PlaybackCoordinator.infuseFilename(
            item: seriesItem(title: "Dark"),
            episode: episode(season: 3, number: 8),
            filename: "Dark.S03E08.1080p.mkv"
        )
        #expect(filename == "Dark S03E08.mkv")
    }

    @Test func episodeFilenamePreservesKnownExtension() {
        let filename = PlaybackCoordinator.infuseFilename(
            item: seriesItem(title: "Dark"),
            episode: episode(season: 1, number: 1),
            filename: "dark.s01e01.mp4"
        )
        #expect(filename == "Dark S01E01.mp4")
    }

    @Test func episodeFilenameNormalizesUnknownExtensionToMkv() {
        let filename = PlaybackCoordinator.infuseFilename(
            item: seriesItem(title: "Dark"),
            episode: episode(season: 2, number: 10),
            filename: "dark.s02e10.strm"
        )
        #expect(filename == "Dark S02E10.mkv")

        let missing = PlaybackCoordinator.infuseFilename(
            item: seriesItem(title: "Dark"),
            episode: episode(season: 2, number: 10),
            filename: nil
        )
        #expect(missing == "Dark S02E10.mkv")
    }

    @Test func fullyEncodesCallbackURLs() throws {
        let video = try #require(URL(string: "https://cdn.example/file.mkv"))
        let item = InfusePlayItem(videoURL: video, filename: nil, positionSeconds: nil)
        let url = try #require(InfuseURLBuilder.playURL(item: item))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(components.percentEncodedQuery)

        #expect(query.contains("x-success=streamhub%3A%2F%2Finfuse%2Fsuccess"))
        #expect(query.contains("x-error=streamhub%3A%2F%2Finfuse%2Ferror"))
        #expect(try value("x-success", in: url) == InfuseURLBuilder.successCallback)
        #expect(try value("x-error", in: url) == InfuseURLBuilder.errorCallback)
    }
}
