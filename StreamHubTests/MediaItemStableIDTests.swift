import Foundation
import Testing
@testable import StreamHub

struct MediaItemStableIDTests {

    private func entry(contentId: String, position: Int = 600) -> ResumeEntry {
        ResumeEntry(
            contentId: contentId,
            imdbId: nil,
            title: "Um Sonho de Liberdade",
            year: 1994,
            posterURL: nil,
            backdropURL: nil,
            logoURL: nil,
            runtimeMinutes: 142,
            positionSeconds: position,
            updatedAt: Date(timeIntervalSince1970: 0),
            serviceCode: nil,
            synopsis: nil,
            genres: nil
        )
    }

    @Test func sameKeyYieldsSameID() {
        #expect(MediaItem.stableID(for: "tt0111161") == MediaItem.stableID(for: "tt0111161"))
    }

    @Test func differentKeysYieldDifferentIDs() {
        #expect(MediaItem.stableID(for: "tt0111161") != MediaItem.stableID(for: "tt0068646"))
        #expect(MediaItem.stableID(for: "") != MediaItem.stableID(for: " "))
    }

    @Test func stableIDIsWellFormedVersion8UUID() {
        let uuid = MediaItem.stableID(for: "tt0111161").uuid
        #expect(uuid.6 >> 4 == 0x8)
        #expect(uuid.8 >> 6 == 0b10)
    }

    @Test func resumeItemKeepsItsIDAcrossRebuilds() {
        let first = MediaItem(entry: entry(contentId: "tt0111161"))
        let rebuilt = MediaItem(entry: entry(contentId: "tt0111161"))
        #expect(first.id == rebuilt.id)
        #expect(first == rebuilt)
    }

    @Test func resumeItemKeepsIdentityWhenProgressChanges() {
        let before = MediaItem(entry: entry(contentId: "tt0111161", position: 600))
        let after = MediaItem(entry: entry(contentId: "tt0111161", position: 1200))
        #expect(before.id == after.id)
        #expect(before != after)
    }

    @Test func distinctResumeEntriesGetDistinctIDs() {
        let ids = ["tt0111161", "tt0068646", "kitsu:1"].map { MediaItem(entry: entry(contentId: $0)).id }
        #expect(Set(ids).count == 3)
    }
}
