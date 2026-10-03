import Foundation
import TVServices

nonisolated final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let defaults = TopShelfStorage.sharedDefaults(),
              let snapshot = TopShelfStorage.load(from: defaults) else {
            return nil
        }
        let artworkDirectory = TopShelfStorage.artworkDirectory()
        let items = snapshot.items.compactMap {
            makeItem($0, profileID: snapshot.profileID, artworkDirectory: artworkDirectory)
        }
        guard !items.isEmpty else { return nil }
        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "Continue assistindo"
        return TVTopShelfSectionedContent(sections: [collection])
    }

    private func makeItem(_ entry: TopShelfSnapshot.Item, profileID: UUID, artworkDirectory: URL?) -> TVTopShelfSectionedItem? {
        let artworkURL = artworkDirectory.flatMap { TopShelfStorage.existingArtworkURL(for: entry, in: $0) }
        guard let imageURL = artworkURL ?? entry.imageURL,
              let displayURL = TopShelfLink(action: .display, profileID: profileID, contentID: entry.contentID).url,
              let playURL = TopShelfLink(action: .play, profileID: profileID, contentID: entry.contentID).url else {
            return nil
        }
        let item = TVTopShelfSectionedItem(identifier: entry.contentID)
        item.title = entry.title
        item.imageShape = .hdtv
        item.setImageURL(imageURL, for: [.screenScale1x, .screenScale2x])
        if let progress = entry.progress, progress > 0 {
            item.playbackProgress = progress
        }
        item.displayAction = TVTopShelfAction(url: displayURL)
        item.playAction = TVTopShelfAction(url: playURL)
        return item
    }
}
