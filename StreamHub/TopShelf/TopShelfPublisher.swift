import Foundation
import TVServices

nonisolated enum TopShelfPublisher {
    static func snapshot(profileID: UUID?, entries: [ResumeEntry]) -> TopShelfSnapshot? {
        guard let profileID else { return nil }
        return TopShelfSnapshot(profileID: profileID, items: entries.map(TopShelfSnapshot.Item.init(entry:)))
    }

    static func publish(_ snapshot: TopShelfSnapshot, to defaults: UserDefaults? = TopShelfStorage.sharedDefaults()) {
        guard let defaults, TopShelfStorage.load(from: defaults) != snapshot else { return }
        TopShelfStorage.save(snapshot, to: defaults)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    static func clear(
        from defaults: UserDefaults? = TopShelfStorage.sharedDefaults(),
        artworkDirectory: URL? = TopShelfStorage.artworkDirectory()
    ) {
        guard let defaults, defaults.data(forKey: TopShelfStorage.snapshotKey) != nil else { return }
        let items = TopShelfStorage.load(from: defaults)?.items ?? []
        defaults.removeObject(forKey: TopShelfStorage.snapshotKey)
        if let artworkDirectory {
            for name in items.compactMap(TopShelfStorage.artworkFileName(for:)) {
                try? FileManager.default.removeItem(at: artworkDirectory.appending(path: name))
            }
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}

nonisolated extension TopShelfSnapshot.Item {
    init(entry: ResumeEntry) {
        self.init(
            contentID: entry.contentId,
            title: [entry.title, entry.episodeCode].compactMap { $0 }.joined(separator: " · "),
            imageURL: entry.backdropURL ?? entry.posterURL,
            logoURL: entry.logoURL,
            progress: entry.progress
        )
    }
}
