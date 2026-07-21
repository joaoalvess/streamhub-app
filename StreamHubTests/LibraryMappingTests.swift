import Foundation
import Testing
@testable import StreamHub

struct LibraryMappingTests {

    private func makeItem(
        id: String = "item-1",
        name: String = "Some File",
        year: Int? = 2020,
        runTimeTicks: Int64? = 36_000_000_000,
        positionTicks: Int64? = nil,
        playedPercentage: Double? = nil,
        primaryTag: String? = "tag-p",
        backdropTags: [String]? = ["tag-b"]
    ) -> JellyfinItem {
        JellyfinItem(
            id: id,
            name: name,
            type: "Movie",
            productionYear: year,
            runTimeTicks: runTimeTicks,
            imageTags: primaryTag.map { ["Primary": $0] },
            backdropImageTags: backdropTags,
            userData: JellyfinUserData(
                playbackPositionTicks: positionTicks,
                playedPercentage: playedPercentage,
                played: false
            )
        )
    }

    @Test func mapsEntryWithImagesAndProgress() throws {
        let base = try #require(URL(string: "https://jellyfin.example"))
        let entry = LibraryEntry(item: makeItem(playedPercentage: 40), base: base)
        #expect(entry.id == "item-1")
        #expect(entry.name == "Some File")
        #expect(entry.year == 2020)
        #expect(entry.progress == 0.4)
        #expect(entry.runtimeMinutes == 60)
        let poster = try #require(entry.posterURL)
        #expect(poster.absoluteString.contains("/Items/item-1/Images/Primary"))
        #expect(poster.absoluteString.contains("tag=tag-p"))
        let backdrop = try #require(entry.backdropURL)
        #expect(backdrop.absoluteString.contains("/Images/Backdrop/0"))
    }

    @Test func entryWithoutTagsHasNoImages() throws {
        let base = try #require(URL(string: "https://jellyfin.example"))
        let entry = LibraryEntry(item: makeItem(primaryTag: nil, backdropTags: nil), base: base)
        #expect(entry.posterURL == nil)
        #expect(entry.backdropURL == nil)
        #expect(entry.progress == nil)
    }

    @Test func startSecondsRequiresMinimumPosition() {
        let short = LibraryEntry(item: makeItem(positionTicks: JellyfinTicks.ticks(seconds: 20)), base: nil)
        #expect(short.startSeconds == nil)
        let resumable = LibraryEntry(item: makeItem(positionTicks: JellyfinTicks.ticks(seconds: 300)), base: nil)
        #expect(resumable.startSeconds == 300)
    }

    @Test func startSecondsDropsNearlyFinishedPlayback() {
        let ticks = JellyfinTicks.ticks(seconds: 3540)
        let entry = LibraryEntry(item: makeItem(positionTicks: ticks), base: nil)
        #expect(entry.startSeconds == nil)
    }

    @Test func startSecondsWithoutRuntimeKeepsPosition() {
        let entry = LibraryEntry(
            item: makeItem(runTimeTicks: nil, positionTicks: JellyfinTicks.ticks(seconds: 90)),
            base: nil
        )
        #expect(entry.startSeconds == 90)
    }

    @Test func buildsSessionMetadataFromEntry() throws {
        let base = try #require(URL(string: "https://jellyfin.example"))
        let entry = LibraryEntry(item: makeItem(), base: base)
        let metadata = entry.sessionMetadata()
        #expect(metadata.year == 2020)
        #expect(metadata.runtimeMinutes == 60)
        #expect(metadata.artworkURL == entry.backdropURL)
    }
}
