import Foundation
import Testing
@testable import StreamHub

struct JellyfinRequestTests {

    @Test func buildsAuthorizationHeaderWithToken() {
        let header = JellyfinSession.authorizationHeader(token: "tok123", deviceId: "device1", version: "1.0")
        #expect(header.hasPrefix("MediaBrowser "))
        #expect(header.contains(#"Client="StreamHub""#))
        #expect(header.contains(#"Device="Apple%20TV""#))
        #expect(header.contains(#"DeviceId="device1""#))
        #expect(header.contains(#"Token="tok123""#))
    }

    @Test func loginHeaderOmitsToken() {
        let header = JellyfinSession.authorizationHeader(token: nil, deviceId: "device1", version: "1.0")
        #expect(header.contains("Token=") == false)
        #expect(header.contains(#"Version="1%2E0""#))
    }

    @Test func derivesStableDeviceId() {
        let first = JellyfinSession.deviceId(vendorId: "VENDOR", username: "someone")
        let second = JellyfinSession.deviceId(vendorId: "VENDOR", username: "someone")
        let other = JellyfinSession.deviceId(vendorId: "VENDOR", username: "another")
        #expect(first == second)
        #expect(first != other)
        #expect(first.hasPrefix("VENDOR-"))
        #expect(first.count == "VENDOR-".count + 8)
    }

    @Test func buildsStreamURL() throws {
        let base = try #require(URL(string: "https://jellyfin.example"))
        let url = try #require(JellyfinAPI.streamURL(base: base, itemId: "item1", token: "tok"))
        let absolute = url.absoluteString
        #expect(absolute.hasPrefix("https://jellyfin.example/Videos/item1/stream?"))
        #expect(absolute.contains("static=true"))
        #expect(absolute.contains("mediaSourceId=item1"))
        #expect(absolute.contains("api_key=tok"))
    }

    @Test func buildsImageURLs() throws {
        let base = try #require(URL(string: "https://jellyfin.example"))
        let poster = try #require(JellyfinAPI.primaryImageURL(base: base, itemId: "item1", tag: "tag1", maxWidth: 536))
        #expect(poster.absoluteString.hasPrefix("https://jellyfin.example/Items/item1/Images/Primary?"))
        #expect(poster.absoluteString.contains("tag=tag1"))
        #expect(poster.absoluteString.contains("maxWidth=536"))
        let backdrop = try #require(JellyfinAPI.backdropImageURL(base: base, itemId: "item1", tag: "tag2", maxWidth: 1920))
        #expect(backdrop.absoluteString.contains("/Images/Backdrop/0?"))
        #expect(backdrop.absoluteString.contains("tag=tag2"))
    }

    @Test func buildsQueryURLKeepingBasePath() throws {
        let base = try #require(URL(string: "https://jellyfin.example"))
        let url = try #require(JellyfinAPI.url(base: base, path: "/UserItems/Resume", query: [
            URLQueryItem(name: "userId", value: "user1"),
            URLQueryItem(name: "mediaTypes", value: "Video")
        ]))
        #expect(url.absoluteString == "https://jellyfin.example/UserItems/Resume?userId=user1&mediaTypes=Video")
    }

    @Test func buildsSearchQuery() {
        let query = JellyfinAPI.searchQuery(userId: "user1", term: "matrix", limit: 60)
        #expect(query.contains(URLQueryItem(name: "userId", value: "user1")))
        #expect(query.contains(URLQueryItem(name: "searchTerm", value: "matrix")))
        #expect(query.contains(URLQueryItem(name: "recursive", value: "true")))
        #expect(query.contains(URLQueryItem(name: "mediaTypes", value: "Video")))
        #expect(query.contains(URLQueryItem(name: "sortBy", value: "SortName")))
        #expect(query.contains(URLQueryItem(name: "limit", value: "60")))
        #expect(query.contains(URLQueryItem(name: "fields", value: "MediaStreams")))
    }

    @Test func buildsPageQuery() {
        let query = JellyfinAPI.pageQuery(userId: "user1", startIndex: 200, limit: 100)
        #expect(query.contains(URLQueryItem(name: "userId", value: "user1")))
        #expect(query.contains(URLQueryItem(name: "recursive", value: "true")))
        #expect(query.contains(URLQueryItem(name: "sortBy", value: "SortName")))
        #expect(query.contains(URLQueryItem(name: "sortOrder", value: "Ascending")))
        #expect(query.contains(URLQueryItem(name: "startIndex", value: "200")))
        #expect(query.contains(URLQueryItem(name: "limit", value: "100")))
        #expect(query.contains(URLQueryItem(name: "fields", value: "MediaStreams")))
    }

    @Test func playbackEventPathsAreCanonical() {
        #expect(JellyfinPlaybackEvent.start.path == "/Sessions/Playing")
        #expect(JellyfinPlaybackEvent.progress.path == "/Sessions/Playing/Progress")
        #expect(JellyfinPlaybackEvent.stopped.path == "/Sessions/Playing/Stopped")
    }
}
