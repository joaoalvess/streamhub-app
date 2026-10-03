import CoreGraphics
import Foundation
import Testing
@testable import StreamHub

struct TopShelfTests {

    private let profileID = UUID()

    private func makeDefaults() throws -> UserDefaults {
        let name = "TopShelfTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func entry(
        contentId: String = "tt0111161",
        metaId: String? = nil,
        backdropURL: URL? = URL(string: "https://img.example/backdrop.jpg"),
        posterURL: URL? = URL(string: "https://img.example/poster.jpg"),
        logoURL: URL? = nil,
        runtimeMinutes: Int? = 100,
        position: Int = 3000,
        season: Int? = nil,
        episode: Int? = nil
    ) -> ResumeEntry {
        ResumeEntry(
            contentId: contentId,
            imdbId: contentId,
            title: "Um Sonho de Liberdade",
            year: 1994,
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            runtimeMinutes: runtimeMinutes,
            positionSeconds: position,
            updatedAt: Date(),
            serviceCode: nil,
            synopsis: nil,
            genres: nil,
            metaId: metaId,
            season: season,
            episode: episode
        )
    }

    @Test(arguments: [TopShelfLink.Action.display, .play], ["tt0111161", "kitsu:12345", "a&b=c+d é"])
    func linkRoundTrips(action: TopShelfLink.Action, contentID: String) throws {
        let link = TopShelfLink(action: action, profileID: profileID, contentID: contentID)
        let url = try #require(link.url)

        #expect(url.scheme == "streamhub")
        #expect(url.host() == "topshelf")
        #expect(TopShelfLink(url: url) == link)
    }

    @Test(arguments: [
        "https://topshelf/play?profile=E621E1F8-C36C-495A-93FC-0C247A3E6E5F&content=tt1",
        "streamhub://infuse/play?profile=E621E1F8-C36C-495A-93FC-0C247A3E6E5F&content=tt1",
        "streamhub://topshelf/pause?profile=E621E1F8-C36C-495A-93FC-0C247A3E6E5F&content=tt1",
        "streamhub://topshelf/play?profile=not-a-uuid&content=tt1",
        "streamhub://topshelf/play?profile=E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        "streamhub://topshelf/play?profile=E621E1F8-C36C-495A-93FC-0C247A3E6E5F&content=",
    ])
    func linkRejectsForeignOrIncompleteURLs(_ raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(TopShelfLink(url: url) == nil)
    }

    @Test func infuseCallbackAndTopShelfLinkDoNotOverlap() throws {
        let topShelf = try #require(TopShelfLink(action: .play, profileID: profileID, contentID: "tt0111161").url)
        let infuse = try #require(URL(string: "streamhub://infuse/success?lastPlayedUrl=x&position=10"))

        #expect(InfuseCallback(url: topShelf) == nil)
        #expect(InfuseCallback(url: infuse) != nil)
        #expect(TopShelfLink(url: infuse) == nil)
    }

    @Test func appGroupIsSharedBetweenAppAndExtension() {
        #expect(TopShelfStorage.appGroupIdentifier(bundleIdentifier: "com.example.app", isExtension: false)
            == "group.com.example.app")
        #expect(TopShelfStorage.appGroupIdentifier(bundleIdentifier: "com.example.app.StreamHubTopShelf", isExtension: true)
            == "group.com.example.app")
    }

    @Test func appGroupRequiresABundleIdentifier() {
        #expect(TopShelfStorage.appGroupIdentifier(bundleIdentifier: "", isExtension: false) == nil)
        #expect(TopShelfStorage.appGroupIdentifier(bundleIdentifier: "single", isExtension: true) == nil)
    }

    @Test func snapshotRoundTripsThroughDefaults() throws {
        let defaults = try makeDefaults()
        let snapshot = try #require(TopShelfPublisher.snapshot(
            profileID: profileID,
            entries: [entry(), entry(contentId: "tt0468569", backdropURL: nil)]
        ))

        TopShelfStorage.save(snapshot, to: defaults)

        #expect(TopShelfStorage.load(from: defaults) == snapshot)
    }

    @Test func corruptedSnapshotLoadsAsNil() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: TopShelfStorage.snapshotKey)

        #expect(TopShelfStorage.load(from: defaults) == nil)
    }

    @Test func itemUsesBackdropAndProgress() {
        let item = TopShelfSnapshot.Item(entry: entry())

        #expect(item.contentID == "tt0111161")
        #expect(item.title == "Um Sonho de Liberdade")
        #expect(item.imageURL == URL(string: "https://img.example/backdrop.jpg"))
        #expect(item.progress == 0.5)
    }

    @Test func itemFallsBackToPosterWithoutBackdrop() {
        let item = TopShelfSnapshot.Item(entry: entry(backdropURL: nil))
        #expect(item.imageURL == URL(string: "https://img.example/poster.jpg"))
    }

    @Test func itemWithoutRuntimeHasNoProgress() {
        #expect(TopShelfSnapshot.Item(entry: entry(runtimeMinutes: nil)).progress == nil)
    }

    @Test func seriesItemShowsEpisodeCodeAndKeepsStoreKey() {
        let item = TopShelfSnapshot.Item(entry: entry(contentId: "tt0903747", metaId: "tmdb:1396", season: 2, episode: 5))

        #expect(item.title == "Um Sonho de Liberdade · T2E5")
        #expect(item.contentID == "tt0903747")
    }

    @Test func snapshotRequiresAProfile() {
        #expect(TopShelfPublisher.snapshot(profileID: nil, entries: [entry()]) == nil)
    }

    @Test func snapshotKeepsEntryOrder() throws {
        let snapshot = try #require(TopShelfPublisher.snapshot(
            profileID: profileID,
            entries: [entry(contentId: "tt1"), entry(contentId: "tt2")]
        ))

        #expect(snapshot.profileID == profileID)
        #expect(snapshot.items.map(\.contentID) == ["tt1", "tt2"])
    }

    @Test func itemCarriesLogo() {
        let logo = URL(string: "https://img.example/logo.png")
        #expect(TopShelfSnapshot.Item(entry: entry(logoURL: logo)).logoURL == logo)
    }

    @Test func artworkNeedsImageAndLogo() {
        let logo = URL(string: "https://img.example/logo.png")

        #expect(TopShelfStorage.artworkFileName(for: .init(entry: entry())) == nil)
        #expect(TopShelfStorage.artworkFileName(for: .init(entry: entry(backdropURL: nil, posterURL: nil, logoURL: logo))) == nil)
        #expect(TopShelfStorage.artworkFileName(for: .init(entry: entry(logoURL: logo))) != nil)
    }

    @Test func artworkNameIsStableAndTracksSources() throws {
        let item = TopShelfSnapshot.Item(entry: entry(logoURL: URL(string: "https://img.example/logo.png")))
        let name = try #require(TopShelfStorage.artworkFileName(for: item))
        let otherLogo = TopShelfSnapshot.Item(entry: entry(logoURL: URL(string: "https://img.example/other.png")))
        let otherContent = TopShelfSnapshot.Item(entry: entry(contentId: "tt0468569", logoURL: URL(string: "https://img.example/logo.png")))

        #expect(TopShelfStorage.artworkFileName(for: item) == name)
        #expect(TopShelfStorage.artworkFileName(for: otherLogo) != name)
        #expect(TopShelfStorage.artworkFileName(for: otherContent) != name)
        #expect(name.hasSuffix(".jpg"))
        #expect(name.dropLast(4).allSatisfy(\.isHexDigit))
    }

    @Test func existingArtworkRequiresTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TopShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = TopShelfSnapshot.Item(entry: entry(logoURL: URL(string: "https://img.example/logo.png")))
        let name = try #require(TopShelfStorage.artworkFileName(for: item))

        #expect(TopShelfStorage.existingArtworkURL(for: item, in: directory) == nil)

        try Data("jpg".utf8).write(to: directory.appending(path: name))

        #expect(TopShelfStorage.existingArtworkURL(for: item, in: directory) == directory.appending(path: name))
    }

    @Test func staleArtworkKeepsOnlyCurrentItems() throws {
        let snapshot = try #require(TopShelfPublisher.snapshot(
            profileID: profileID,
            entries: [entry(contentId: "tt1", logoURL: URL(string: "https://img.example/logo.png")), entry(contentId: "tt2")]
        ))
        let current = try #require(snapshot.items.first.flatMap(TopShelfStorage.artworkFileName(for:)))

        #expect(TopShelfArtwork.staleArtwork([current, "old.jpg"], keeping: snapshot) == ["old.jpg"])
    }

    @Test func renderedArtworkHasTheRequestedSize() throws {
        let backdrop = try #require(solidImage(width: 320, height: 180))
        let logo = try #require(solidImage(width: 80, height: 30))
        let artwork = try #require(TopShelfArtwork.render(backdrop: backdrop, logo: logo, width: 400, height: 225))

        #expect(artwork.width == 400)
        #expect(artwork.height == 225)
    }

    private func solidImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
