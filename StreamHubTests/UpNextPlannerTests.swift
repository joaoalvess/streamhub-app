import Foundation
import Testing
@testable import StreamHub

struct UpNextPlannerTests {

    private func streams(_ json: String) throws -> [AddonStream] {
        try JSONDecoder().decode(StreamsResponse.self, from: Data(json.utf8)).streams
    }

    private func episode(season: Int = 1, number: Int = 2, title: String = "Gato no Saco") -> EpisodeItem {
        EpisodeItem(
            videoId: "tt0903747:\(season):\(number)",
            season: season,
            episode: number,
            title: title,
            overview: nil,
            thumbnailURL: nil,
            releasedAt: nil,
            runtimeMinutes: 47,
            isReleased: true
        )
    }

    @Test func prefetchStartsInsideTheLeadWindow() {
        #expect(UpNextPlanner.shouldPrefetch(position: 1380, duration: 1500))
        #expect(UpNextPlanner.shouldPrefetch(position: 1499, duration: 1500))
        #expect(!UpNextPlanner.shouldPrefetch(position: 1379, duration: 1500))
    }

    @Test func prefetchNeedsAKnownDurationAndPosition() {
        #expect(!UpNextPlanner.shouldPrefetch(position: 1400, duration: nil))
        #expect(!UpNextPlanner.shouldPrefetch(position: 1400, duration: 0))
        #expect(!UpNextPlanner.shouldPrefetch(position: 0, duration: 1500))
    }

    @Test func prefetchHonorsCustomLead() {
        #expect(UpNextPlanner.shouldPrefetch(position: 1440, duration: 1500, lead: 60))
        #expect(!UpNextPlanner.shouldPrefetch(position: 1439, duration: 1500, lead: 60))
    }

    @Test func streamPrefersTheSameBingeGroup() throws {
        let list = try streams("""
        {"streams":[
            {"name":"B","url":"https://cdn/b.mkv","behaviorHints":{"bingeGroup":"group-b"}},
            {"name":"A","url":"https://cdn/a.mkv","behaviorHints":{"bingeGroup":"group-a"}}
        ]}
        """)

        let chosen = UpNextPlanner.stream(in: list, bingeGroup: "group-a")

        #expect(chosen?.playbackURL?.absoluteString == "https://cdn/a.mkv")
    }

    @Test func streamFallsBackToFirstPlayableWithoutMatch() throws {
        let list = try streams("""
        {"streams":[
            {"name":"Estatística","url":"https://cdn/stat","streamData":{"type":"statistic"}},
            {"name":"Externo","externalUrl":"https://site/x"},
            {"name":"B","url":"https://cdn/b.mkv","behaviorHints":{"bingeGroup":"group-b"}},
            {"name":"C","url":"https://cdn/c.mkv"}
        ]}
        """)

        #expect(UpNextPlanner.stream(in: list, bingeGroup: "group-a")?.playbackURL?.absoluteString == "https://cdn/b.mkv")
        #expect(UpNextPlanner.stream(in: list, bingeGroup: nil)?.playbackURL?.absoluteString == "https://cdn/b.mkv")
    }

    @Test func streamIgnoresUnplayableBingeGroupMatch() throws {
        let list = try streams("""
        {"streams":[
            {"name":"A","externalUrl":"https://site/a","behaviorHints":{"bingeGroup":"group-a"}},
            {"name":"B","url":"https://cdn/b.mkv","behaviorHints":{"bingeGroup":"group-b"}}
        ]}
        """)

        #expect(UpNextPlanner.stream(in: list, bingeGroup: "group-a")?.playbackURL?.absoluteString == "https://cdn/b.mkv")
        #expect(UpNextPlanner.stream(in: [], bingeGroup: "group-a") == nil)
    }

    @Test func sourceOptionsMarkCurrentAndDeduplicate() throws {
        let list = try streams("""
        {"streams":[
            {"name":"[TB+] 1080p","description":"Arquivo.mkv\\n2 GB","url":"https://cdn/a.mkv"},
            {"url":"https://cdn/b.mkv"},
            {"name":"Repetida","url":"https://cdn/a.mkv"}
        ]}
        """)

        let options = UpNextPlanner.sourceOptions(from: list, current: URL(string: "https://cdn/b.mkv"))

        #expect(options.map(\.id) == ["https://cdn/a.mkv", "https://cdn/b.mkv"])
        #expect(options.map(\.title) == ["[TB+] 1080p", "Fonte"])
        #expect(options.first?.subtitle == "Arquivo.mkv\n2 GB")
        #expect(options.map(\.isSelected) == [false, true])
    }

    @Test func upNextSubtitleCombinesCodeAndTitle() {
        #expect(UpNextPlanner.upNextSubtitle(for: episode()) == "T1E2 · Gato no Saco")
        #expect(UpNextPlanner.upNextSubtitle(for: episode(season: 3, number: 7, title: "")) == "T3E7")
    }
}
