import Foundation
import Testing
@testable import StreamHub

struct TopShelfPublisherClearTests {

    private func makeDefaults() throws -> UserDefaults {
        let name = "TopShelfPublisherClearTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TopShelfPublisherClearTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func item(_ contentID: String, withLogo: Bool = true) -> TopShelfSnapshot.Item {
        TopShelfSnapshot.Item(
            contentID: contentID,
            title: "Título \(contentID)",
            imageURL: URL(string: "https://img.example/\(contentID)-backdrop.jpg"),
            logoURL: withLogo ? URL(string: "https://img.example/\(contentID)-logo.png") : nil,
            progress: 0.4
        )
    }

    private func writeArtwork(for item: TopShelfSnapshot.Item, in directory: URL) throws -> URL {
        let name = try #require(TopShelfStorage.artworkFileName(for: item))
        let url = directory.appending(path: name)
        try Data("jpg".utf8).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func removesTheSnapshotAndItsArtwork() throws {
        let defaults = try makeDefaults()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = item("tt1")
        let second = item("tt2")
        TopShelfStorage.save(
            TopShelfSnapshot(profileID: UUID(), items: [first, second, item("tt3", withLogo: false)]),
            to: defaults
        )
        let firstArtwork = try writeArtwork(for: first, in: directory)
        let secondArtwork = try writeArtwork(for: second, in: directory)

        TopShelfPublisher.clear(from: defaults, artworkDirectory: directory)

        #expect(defaults.data(forKey: TopShelfStorage.snapshotKey) == nil)
        #expect(TopShelfStorage.load(from: defaults) == nil)
        #expect(!exists(firstArtwork))
        #expect(!exists(secondArtwork))
    }

    @Test func removesTheSnapshotWithoutAnArtworkDirectory() throws {
        let defaults = try makeDefaults()
        TopShelfStorage.save(TopShelfSnapshot(profileID: UUID(), items: [item("tt1")]), to: defaults)

        TopShelfPublisher.clear(from: defaults, artworkDirectory: nil)

        #expect(defaults.data(forKey: TopShelfStorage.snapshotKey) == nil)
    }

    @Test func removesACorruptedSnapshot() throws {
        let defaults = try makeDefaults()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        defaults.set(Data("not json".utf8), forKey: TopShelfStorage.snapshotKey)

        TopShelfPublisher.clear(from: defaults, artworkDirectory: directory)

        #expect(defaults.data(forKey: TopShelfStorage.snapshotKey) == nil)
    }

    @Test func withoutASnapshotLeavesArtworkUntouched() throws {
        let defaults = try makeDefaults()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artwork = try writeArtwork(for: item("tt1"), in: directory)

        TopShelfPublisher.clear(from: defaults, artworkDirectory: directory)
        TopShelfPublisher.clear(from: nil, artworkDirectory: directory)

        #expect(exists(artwork))
        #expect(defaults.data(forKey: TopShelfStorage.snapshotKey) == nil)
    }
}
