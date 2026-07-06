import Foundation
import Testing
@testable import StreamHub

struct StreamSelectorTests {

    private func stream(_ json: String) throws -> AddonStream {
        try JSONDecoder().decode(AddonStream.self, from: Data(json.utf8))
    }

    private var dubbed4KCached: String {
        """
        {"name":"[TB+] StremThru Torz 2160p",
         "description":"Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv\\n💾6.74 GiB 👤5 \\n🇵🇹 / 🇬🇧 Subs / 🇧🇷 / 🇬🇧",
         "url":"https://resolve.example/a.mkv",
         "behaviorHints":{"bingeGroup":"com.aiostreams.viren070|torbox|false|2160p|BluRay|HEVC|DD|Portuguese|English|andrehsa",
                          "videoSize":7237543248,
                          "filename":"Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv"}}
        """
    }

    private var english4KDV: String {
        """
        {"name":"[TB+] Torrentio 2160p\\n10bit | HDR | DV",
         "description":"The.Shawshank.Redemption.1994.2160p.UHD.BluRay.x265-TERMiNAL.mkv\\n💾22.50 GiB 👤48 ⚙️RARBG\\n🇬🇧",
         "url":"https://resolve.example/b.mkv",
         "behaviorHints":{"bingeGroup":"com.aiostreams.viren070|torbox|false|2160p|BluRay|HEVC|DDP|English|TERMiNAL",
                          "videoSize":24159191040,
                          "filename":"The.Shawshank.Redemption.1994.2160p.UHD.BluRay.x265-TERMiNAL.mkv"}}
        """
    }

    private var dubbed1080Cached: String {
        """
        {"name":"[TB+] Comet 1080p",
         "description":"Um Sonho de Liberdade 1080p (1994) Dual Áudio BluRay\\nUm.Sonho.de.Liberdade.1994.1080p.mkv\\n💾2.10 GiB 👤12 ⚙️Comando\\n🇧🇷 / 🇬🇧",
         "url":"https://resolve.example/c.mkv",
         "behaviorHints":{"bingeGroup":"com.aiostreams.viren070|torbox|false|1080p|BluRay|AVC|DD|Portuguese|English|Comando",
                          "videoSize":2254857830,
                          "filename":"Um.Sonho.de.Liberdade.1994.1080p.mkv"}}
        """
    }

    private var ptOnly2160Uncached: String {
        """
        {"name":"[TB] Torrentio 2160p",
         "description":"Um.Sonho.de.Liberdade.1994.2160p.DUBLADO.mkv\\n💾8.00 GiB 👤3 ⚙️Comando\\n🇧🇷",
         "url":"https://resolve.example/d.mkv",
         "behaviorHints":{"bingeGroup":"com.aiostreams.viren070|torbox|false|2160p|WEB-DL|HEVC|DD|Portuguese|dub",
                          "videoSize":8589934592,
                          "filename":"Um.Sonho.de.Liberdade.1994.2160p.DUBLADO.mkv"}}
        """
    }

    private var scrapeSummary: String {
        """
        {"name":"🟢 [Torrentio TB] Scrape Summary",
         "description":"✔ Status      : SUCCESS\\n📦 Streams    : 157",
         "externalUrl":"https://github.com/Viren070/AIOStreams",
         "streamData":{"type":"statistic"}}
        """
    }

    private var genericMismatch: String {
        """
        {"name":"[TB+] Torrentio 1080p",
         "description":"Another.Movie.Entirely.2003.1080p.mkv\\n💾1.20 GiB 👤9\\n🇬🇧",
         "url":"https://resolve.example/e.mkv",
         "behaviorHints":{"bingeGroup":"com.aiostreams.viren070|torbox|false|1080p|BluRay|AVC|DD|English|grp",
                          "videoSize":1288490188,
                          "filename":"Another.Movie.Entirely.2003.1080p.mkv"}}
        """
    }

    @Test func parsesCandidateFieldsFromRealStream() throws {
        let candidate = try #require(StreamCandidate(stream: stream(dubbed4KCached)))
        #expect(candidate.isCached)
        #expect(candidate.resolution == 2160)
        #expect(candidate.hasPTAudio)
        #expect(candidate.hasOriginalAudio)
        #expect(candidate.sizeBytes == 7_237_543_248)
        #expect(candidate.seeds == 5)
    }

    @Test func parsesHDRFlagsAndUncachedTag() throws {
        let dv = try #require(StreamCandidate(stream: stream(english4KDV)))
        #expect(dv.hdrScore == 7)
        #expect(dv.isCached)
        let uncached = try #require(StreamCandidate(stream: stream(ptOnly2160Uncached)))
        #expect(!uncached.isCached)
    }

    @Test func parsesSizeFromDescriptionWhenHintMissing() throws {
        let json = """
        {"name":"[TB+] Comet 720p",
         "description":"file.mkv\\n💾1.5 GiB 👤2\\n🇬🇧",
         "url":"https://resolve.example/f.mkv"}
        """
        let candidate = try #require(StreamCandidate(stream: stream(json)))
        #expect(candidate.sizeBytes == Int64(1.5 * 1_073_741_824))
        #expect(candidate.resolution == 720)
    }

    @Test func playableFiltersScrapeSummaries() throws {
        let streams = [try stream(scrapeSummary), try stream(dubbed4KCached)]
        let candidates = StreamSelector.playable(from: streams)
        #expect(candidates.count == 1)
    }

    @Test func validationRejectsGenericStreamAndKeepsEnglishRelease() throws {
        let candidates = StreamSelector.playable(from: [
            try stream(genericMismatch),
            try stream(english4KDV)
        ])
        let validated = StreamSelector.validated(candidates, title: "Um Sonho de Liberdade", year: 1994)
        #expect(validated.count == 1)
        #expect(validated.first?.matchText.contains("Shawshank") == true)
    }

    @Test func dubbedPrefersCachedPTOverHigherResolutionUncached() throws {
        let candidates = StreamSelector.playable(from: [
            try stream(ptOnly2160Uncached),
            try stream(dubbed1080Cached),
            try stream(english4KDV)
        ])
        let best = try #require(StreamSelector.best(candidates, mode: .dubbed))
        #expect(best.resolution == 1080)
        #expect(best.hasPTAudio)
        #expect(best.isCached)
    }

    @Test func dubbedPrefersHighestQualityWithinPTGroup() throws {
        let candidates = StreamSelector.playable(from: [
            try stream(dubbed1080Cached),
            try stream(dubbed4KCached),
            try stream(english4KDV)
        ])
        let best = try #require(StreamSelector.best(candidates, mode: .dubbed))
        #expect(best.resolution == 2160)
        #expect(best.hasPTAudio)
    }

    @Test func dubbedFallsBackToBestOverallWhenNoPT() throws {
        let candidates = StreamSelector.playable(from: [try stream(english4KDV)])
        let best = try #require(StreamSelector.best(candidates, mode: .dubbed))
        #expect(!best.hasPTAudio)
        #expect(best.resolution == 2160)
    }

    @Test func subtitledPenalizesPTOnlyRelease() throws {
        let candidates = StreamSelector.playable(from: [
            try stream(ptOnly2160Uncached),
            try stream(english4KDV)
        ])
        let best = try #require(StreamSelector.best(candidates, mode: .subtitled))
        #expect(best.hasOriginalAudio)
        #expect(best.matchText.contains("Shawshank"))
    }

    @Test func enhancedSelectsNothing() throws {
        let candidates = StreamSelector.playable(from: [try stream(dubbed4KCached)])
        #expect(StreamSelector.best(candidates, mode: .enhanced) == nil)
    }

    @Test func titleMatchToleratesYearOffByOne() {
        #expect(StreamSelector.matchesTitleYear(
            "Some.Release.1995.2160p.mkv", title: "Um Sonho de Liberdade", year: 1994
        ))
        #expect(!StreamSelector.matchesTitleYear(
            "Another.Movie.Entirely.2003.1080p.mkv", title: "Um Sonho de Liberdade", year: 1994
        ))
    }
}
