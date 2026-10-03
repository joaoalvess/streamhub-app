import Foundation
import Testing
@testable import StreamHub

struct MediaQualityTests {

    @Test func parsesRealTorBoxStream() throws {
        let json = Data("""
        {"streams":[{
            "name":"[TB+] StremThru Torz 2160p",
            "description":"Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv\\n💾6.74 GiB 👤5 \\n🇵🇹 / 🇬🇧 Subs / 🇧🇷 / 🇬🇧",
            "url":"https://stremthru.example.xyz/stremio/torz/abc/strem/tt0111161/tb/445bd77/0/file.mkv",
            "behaviorHints":{
                "bingeGroup":"com.aiostreams.viren070|torbox|false|2160p|BluRay|HEVC|DD|Portuguese|English|andrehsa",
                "videoSize":7237543248,
                "filename":"Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv"
            }
        }]}
        """.utf8)
        let stream = try #require(try JSONDecoder().decode(StreamsResponse.self, from: json).streams.first)
        let quality = StreamQualityParser.parse(stream)
        #expect(quality.resolution == .uhd)
        #expect(quality.dynamicRange.isEmpty)
        #expect(quality.audio == [.dolbyDigital])
        #expect(quality.channels == .surround51)
        #expect(quality.hasPortugueseSubtitles == false)
        #expect(quality.badges == ["4K", "5.1"])
    }

    @Test func parsesRealAnimeStreamWithoutYear() {
        let quality = StreamQualityParser.parse(
            name: "[TB+] Torrentio 1080p",
            description: nil,
            filename: "[224] Death Note - 01 [BDRip.1080p.x265.FLAC].mkv",
            bingeGroup: "com.aiostreams.viren070|torbox|false|1080p|BluRay|HEVC|FLAC|Japanese|English"
        )
        #expect(quality.resolution == .fullHD)
        #expect(quality.badges.isEmpty)
        #expect(quality.compactBadges == ["1080p"])
    }

    @Test func secondNameLineWithHDRAndDolbyVisionShowsOnlyDolbyVision() {
        let quality = StreamQualityParser.parse(
            name: "[TB+] StremThru Torz 2160p\nHDR | DV",
            description: nil,
            filename: nil,
            bingeGroup: nil
        )
        #expect(quality.dynamicRange == [.dolbyVision, .hdr10])
        #expect(quality.badges == ["4K", "Dolby Vision"])
        #expect(quality.compactBadges == ["4K", "DV"])
    }

    @Test func secondNameLineWithBitDepthAndHDR() {
        let quality = StreamQualityParser.parse(
            name: "[TB+] Comet 2160p\n10bit | HDR",
            description: nil,
            filename: nil,
            bingeGroup: nil
        )
        #expect(quality.dynamicRange == [.hdr10])
        #expect(quality.badges == ["4K", "HDR"])
    }

    @Test func hdr10PlusReplacesPlainHDR() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Movie.2021.2160p.WEB-DL.DDP5.1.Atmos.HDR10+.H265-GRP.mkv",
            bingeGroup: nil
        )
        #expect(quality.dynamicRange.contains(.hdr10Plus))
        #expect(quality.badges == ["4K", "HDR10+", "Dolby Atmos", "5.1"])
        #expect(quality.compactBadges == ["4K", "HDR"])
    }

    @Test func dolbyVisionTokenInFilenameHidesHDR10BaseLayer() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Movie.2023.2160p.WEB-DL.DV.HDR10.DDP5.1.H265-GRP.mkv",
            bingeGroup: nil
        )
        #expect(quality.dynamicRange == [.dolbyVision, .hdr10])
        #expect(quality.badges == ["4K", "Dolby Vision", "5.1"])
    }

    @Test func dolbyDigitalPlusWithAtmos() {
        let quality = StreamQualityParser.parse(
            name: "[TB+] Torrentio 1080p",
            description: nil,
            filename: "Movie.2022.1080p.WEB-DL.DDP5.1.Atmos.H.264-GRP.mkv",
            bingeGroup: nil
        )
        #expect(quality.audio == [.dolbyDigitalPlus, .atmos])
        #expect(quality.channels == .surround51)
        #expect(quality.badges == ["Dolby Atmos", "5.1"])
    }

    @Test func trueHDSevenOneAtmos() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Movie.2019.2160p.UHD.BluRay.REMUX.HDR.HEVC.TrueHD.7.1.Atmos-GRP.mkv",
            bingeGroup: nil
        )
        #expect(quality.audio == [.trueHD, .atmos])
        #expect(quality.channels == .surround71)
        #expect(quality.badges == ["4K", "HDR", "Dolby Atmos", "7.1"])
    }

    @Test func dtsHDMasterAudioSevenOne() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Movie.2010.1080p.BluRay.REMUX.AVC.DTS-HD.MA.7.1-GRP.mkv",
            bingeGroup: nil
        )
        #expect(quality.audio == [.dtsHD])
        #expect(quality.channels == .surround71)
    }

    @Test func dvdTokensAreNotDolbyVision() {
        let withYear = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "The.DVD.Club.2004.DVDRip.XviD-GRP.avi",
            bingeGroup: nil
        )
        let withoutYear = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Some.Movie.DVDRip.XviD-GRP.avi",
            bingeGroup: nil
        )
        #expect(withYear.dynamicRange.isEmpty)
        #expect(withoutYear.dynamicRange.isEmpty)
    }

    @Test func titleWordsBeforeTheYearAreIgnored() {
        let atmosTitle = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Atmos.2019.1080p.WEB-DL.DDP5.1.H264-GRP.mkv",
            bingeGroup: nil
        )
        let hdrTitle = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "The.Hdr.Project.2018.1080p.BluRay.x264-GRP.mkv",
            bingeGroup: nil
        )
        #expect(atmosTitle.audio == [.dolbyDigitalPlus])
        #expect(atmosTitle.badges == ["5.1"])
        #expect(hdrTitle.dynamicRange.isEmpty)
    }

    @Test func titleWordsBeforeEpisodeMarkerAreIgnored() {
        #expect(StreamQualityParser.technicalPart(of: "Atmos.S01E02.1080p.WEB-DL.mkv") == ".1080p.WEB-DL.mkv")
        #expect(StreamQualityParser.technicalPart(of: "2001.A.Space.Odyssey.1968.2160p.mkv") == ".2160p.mkv")
        #expect(StreamQualityParser.technicalPart(of: "[224] Death Note - 01.mkv") == "[224] Death Note - 01.mkv")
    }

    @Test func releaseGroupContainingDVIsNotDolbyVision() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: nil,
            filename: "Movie.2020.2160p.WEB-DL.DDP5.1.HEVC-ADVANCE.mkv",
            bingeGroup: "com.aiostreams.viren070|torbox|false|2160p|WEB-DL|HEVC|DD+|English|DVSKY"
        )
        #expect(quality.dynamicRange.isEmpty)
        #expect(quality.badges == ["4K", "5.1"])
    }

    @Test func unknownQualityHasNoResolution() {
        let quality = StreamQualityParser.parse(
            name: "[TB+] Torrentio Unknown",
            description: nil,
            filename: "Movie.2020.WEB.H264-GRP.mkv",
            bingeGroup: "com.aiostreams.viren070|torbox|false|Unknown|WEB|AVC|Unknown|English|GRP"
        )
        #expect(quality.resolution == nil)
        #expect(quality.badges.isEmpty)
        #expect(quality.compactBadges.isEmpty)
    }

    @Test func portugueseSubtitlesShowLeg() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: "Movie.2020.1080p.mkv\n💾2.10 GiB 👤12\n🇬🇧 / 🇧🇷 Subs",
            filename: nil,
            bingeGroup: nil
        )
        #expect(quality.hasPortugueseSubtitles)
        #expect(quality.badges == ["LEG"])
    }

    @Test func foreignSubtitlesWithPortugueseAudioDoNotShowLeg() {
        let quality = StreamQualityParser.parse(
            name: nil,
            description: "Movie.2020.1080p.mkv\n💾2.10 GiB 👤12\n🇧🇷 / 🇬🇧 Subs",
            filename: nil,
            bingeGroup: nil
        )
        #expect(quality.hasPortugueseSubtitles == false)
    }

    @Test func jellyfinDolbyVisionSevenOneAndClosedCaptions() {
        let quality = MediaQuality(jellyfin: [
            JellyfinMediaStream(type: "Video", height: 2160, videoRangeType: "DOVI"),
            JellyfinMediaStream(type: "Audio", language: "eng", channels: 8),
            JellyfinMediaStream(type: "Subtitle", language: "eng", isHearingImpaired: true)
        ])
        #expect(quality.resolution == .uhd)
        #expect(quality.dynamicRange == [.dolbyVision])
        #expect(quality.channels == .surround71)
        #expect(quality.hasClosedCaptions)
        #expect(quality.hasPortugueseSubtitles == false)
        #expect(quality.badges == ["4K", "Dolby Vision", "7.1", "CC"])
    }

    @Test func jellyfinVideoRangeTypes() {
        func ranges(_ type: String?, range: String? = nil) -> Set<MediaQuality.DynamicRange> {
            MediaQuality(jellyfin: [
                JellyfinMediaStream(type: "Video", height: 2160, videoRange: range, videoRangeType: type)
            ]).dynamicRange
        }
        #expect(ranges("DOVIWithHDR10") == [.dolbyVision, .hdr10])
        #expect(ranges("DOVIWithHDR10Plus") == [.dolbyVision, .hdr10Plus])
        #expect(ranges("HDR10Plus") == [.hdr10Plus])
        #expect(ranges("HLG") == [.hlg])
        #expect(ranges("SDR", range: "SDR").isEmpty)
        #expect(ranges("DOVIInvalid", range: "HDR") == [.hdr10])
    }

    @Test func jellyfinScopeWidthCountsAs4K() {
        let streams = [JellyfinMediaStream(type: "Video", height: 1608, width: 3840)]
        #expect(MediaQuality(jellyfin: streams).resolution == .uhd)
        #expect(LibraryEntry.resolutionBadge(streams: streams) == "4K")
    }

    @Test func decodesRealJellyfinMediaStreams() throws {
        let json = Data("""
        {"Id":"abc","Name":"Filme","Type":"Movie","ProductionYear":2019,"MediaStreams":[
            {"Codec":"hevc","Type":"Video","Width":3840,"Height":1608,"VideoRange":"HDR","VideoRangeType":"DOVIWithHDR10","DisplayTitle":"4K HEVC Dolby Vision Profile 8.1 (HDR10)"},
            {"Codec":"truehd","Type":"Audio","Language":"eng","Channels":8,"Profile":"Dolby TrueHD + Dolby Atmos","DisplayTitle":"English - Dolby TrueHD + Dolby Atmos - 7.1 - Default","IsHearingImpaired":false},
            {"Codec":"ac3","Type":"Audio","Language":"por","Channels":6,"Title":"Audiodescrição","DisplayTitle":"Audiodescrição - Portuguese - Dolby Digital - 5.1"},
            {"Codec":"subrip","Type":"Subtitle","Language":"por","IsHearingImpaired":false,"DisplayTitle":"Portuguese - SUBRIP"},
            {"Codec":"subrip","Type":"Subtitle","Language":"eng","IsHearingImpaired":true,"Title":"English SDH","DisplayTitle":"English SDH - SUBRIP"}
        ]}
        """.utf8)
        let item = try JSONDecoder().decode(JellyfinItem.self, from: json)
        let streams = try #require(item.mediaStreams)
        let video = try #require(streams.first)
        #expect(video.width == 3840)
        #expect(video.videoRangeType == "DOVIWithHDR10")
        #expect(streams[1].channels == 8)
        #expect(streams[1].profile == "Dolby TrueHD + Dolby Atmos")
        #expect(streams[4].isHearingImpaired == true)
        let quality = MediaQuality(jellyfin: streams)
        #expect(quality.audio == [.trueHD, .atmos, .dolbyDigital])
        #expect(quality.hasAudioDescription)
        #expect(quality.badges == ["4K", "Dolby Vision", "Dolby Atmos", "7.1", "LEG", "CC", "AD"])
        #expect(quality.compactBadges == ["4K", "DV"])
    }

    @Test func libraryEntryExposesCompactBadges() {
        let item = JellyfinItem(
            id: "item-1",
            name: "Filme",
            type: "Movie",
            productionYear: 2020,
            runTimeTicks: nil,
            imageTags: nil,
            backdropImageTags: nil,
            userData: nil,
            mediaStreams: [
                JellyfinMediaStream(type: "Video", height: 1080, videoRange: "HDR", videoRangeType: "HDR10"),
                JellyfinMediaStream(type: "Audio", language: "por")
            ]
        )
        let entry = LibraryEntry(item: item, base: nil)
        #expect(entry.quality.compactBadges == ["1080p", "HDR"])
        #expect(entry.resolutionLabel == "1080p")
        #expect(entry.audioLabel == "DUB")
    }

    @Test func badgesFollowFixedOrder() {
        let quality = MediaQuality(
            resolution: .uhd,
            dynamicRange: [.hdr10, .hdr10Plus, .dolbyVision],
            audio: [.dolbyDigitalPlus, .atmos],
            channels: .surround71,
            hasPortugueseSubtitles: true,
            hasClosedCaptions: true,
            hasAudioDescription: true
        )
        #expect(quality.badges == ["4K", "Dolby Vision", "Dolby Atmos", "7.1", "LEG", "CC", "AD"])
    }

    @Test func detailBadgesSkipNonUHDResolutions() {
        #expect(MediaQuality(resolution: .fullHD).badges.isEmpty)
        #expect(MediaQuality(resolution: .hd, dynamicRange: [.hlg]).badges == ["HDR"])
        #expect(MediaQuality(resolution: .sd).compactBadges == ["SD"])
        #expect(MediaQuality().badges.isEmpty)
    }
}
