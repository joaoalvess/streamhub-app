import Foundation

nonisolated enum JellyfinTicks {
    static let perSecond: Int64 = 10_000_000

    static func seconds(_ ticks: Int64) -> Int {
        Int(ticks / perSecond)
    }

    static func ticks(seconds: Int) -> Int64 {
        Int64(seconds) * perSecond
    }
}

nonisolated struct JellyfinAuthResult: Decodable, Sendable {
    let accessToken: String
    let user: JellyfinAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

nonisolated struct JellyfinAuthUser: Decodable, Sendable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

nonisolated struct JellyfinQueryResult: Decodable, Sendable {
    let items: [JellyfinItem]
    let totalRecordCount: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

nonisolated struct JellyfinMediaStream: Decodable, Sendable {
    let type: String?
    let height: Int?
    let language: String?
    let width: Int?
    let codec: String?
    let profile: String?
    let title: String?
    let displayTitle: String?
    let channels: Int?
    let videoRange: String?
    let videoRangeType: String?
    let isHearingImpaired: Bool?

    init(
        type: String?,
        height: Int? = nil,
        language: String? = nil,
        width: Int? = nil,
        codec: String? = nil,
        profile: String? = nil,
        title: String? = nil,
        displayTitle: String? = nil,
        channels: Int? = nil,
        videoRange: String? = nil,
        videoRangeType: String? = nil,
        isHearingImpaired: Bool? = nil
    ) {
        self.type = type
        self.height = height
        self.language = language
        self.width = width
        self.codec = codec
        self.profile = profile
        self.title = title
        self.displayTitle = displayTitle
        self.channels = channels
        self.videoRange = videoRange
        self.videoRangeType = videoRangeType
        self.isHearingImpaired = isHearingImpaired
    }

    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case height = "Height"
        case language = "Language"
        case width = "Width"
        case codec = "Codec"
        case profile = "Profile"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case channels = "Channels"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case isHearingImpaired = "IsHearingImpaired"
    }
}

nonisolated extension JellyfinMediaStream {
    var dynamicRanges: Set<MediaQuality.DynamicRange> {
        let rangeType = (videoRangeType ?? "").lowercased()
        var ranges: Set<MediaQuality.DynamicRange> = []
        if rangeType.hasPrefix("dovi"), rangeType != "doviinvalid" {
            ranges.insert(.dolbyVision)
        }
        if rangeType.contains("hdr10plus") {
            ranges.insert(.hdr10Plus)
        } else if rangeType.contains("hdr10") {
            ranges.insert(.hdr10)
        }
        if rangeType.contains("hlg") {
            ranges.insert(.hlg)
        }
        if ranges.isEmpty, videoRange?.caseInsensitiveCompare("HDR") == .orderedSame {
            ranges.insert(.hdr10)
        }
        return ranges
    }

    var audioFormats: Set<MediaQuality.AudioFormat> {
        let details = [profile, displayTitle].compactMap { $0 }.joined(separator: " ").lowercased()
        var formats: Set<MediaQuality.AudioFormat> = []
        if details.contains("atmos") {
            formats.insert(.atmos)
        }
        switch (codec ?? "").lowercased() {
        case "truehd":
            formats.insert(.trueHD)
        case "eac3":
            formats.insert(.dolbyDigitalPlus)
        case "ac3":
            formats.insert(.dolbyDigital)
        case "dts", "dca":
            if details.contains("dts:x") || details.contains("dts-x") {
                formats.insert(.dtsX)
            } else if details.contains("dts-hd") {
                formats.insert(.dtsHD)
            } else {
                formats.insert(.dts)
            }
        default:
            break
        }
        return formats
    }

    var isAudioDescription: Bool {
        [title, displayTitle].contains { label in
            guard let label = label?.lowercased() else { return false }
            return label.contains("audio description") || label.contains("audiodescri")
        }
    }
}

nonisolated extension MediaQuality {
    init(jellyfin streams: [JellyfinMediaStream]) {
        let video = streams.filter { $0.type == "Video" }
        let audio = streams.filter { $0.type == "Audio" }
        let subtitles = streams.filter { $0.type == "Subtitle" }
        self.init(
            resolution: video.compactMap { Resolution(width: $0.width, height: $0.height) }.max(),
            dynamicRange: Set(video.flatMap(\.dynamicRanges)),
            audio: Set(audio.flatMap(\.audioFormats)),
            channels: audio.compactMap { $0.channels.flatMap(Channels.init(count:)) }.max(),
            hasPortugueseSubtitles: subtitles.contains { $0.language.map(LibraryEntry.isPortuguese) ?? false },
            hasClosedCaptions: subtitles.contains { $0.isHearingImpaired == true },
            hasAudioDescription: audio.contains(where: \.isAudioDescription)
        )
    }
}

nonisolated struct JellyfinItem: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let type: String?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let userData: JellyfinUserData?
    let mediaStreams: [JellyfinMediaStream]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case userData = "UserData"
        case mediaStreams = "MediaStreams"
    }
}

nonisolated struct JellyfinUserData: Decodable, Sendable {
    let playbackPositionTicks: Int64?
    let playedPercentage: Double?
    let played: Bool?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case played = "Played"
    }
}

nonisolated extension JellyfinItem {
    var primaryImageTag: String? {
        imageTags?["Primary"]
    }

    var backdropImageTag: String? {
        backdropImageTags?.first
    }

    var runtimeMinutes: Int? {
        guard let runTimeTicks, runTimeTicks > 0 else { return nil }
        let minutes = Int(runTimeTicks / (JellyfinTicks.perSecond * 60))
        return minutes > 0 ? minutes : nil
    }

    var positionSeconds: Int? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return JellyfinTicks.seconds(ticks)
    }
}

nonisolated struct JellyfinPlaybackReport: Encodable, Sendable {
    let itemId: String
    let playSessionId: String
    let positionTicks: Int64
    let playMethod: String
    let canSeek: Bool
    let isPaused: Bool?

    init(itemId: String, playSessionId: String, positionSeconds: Int, isPaused: Bool? = false) {
        self.itemId = itemId
        self.playSessionId = playSessionId
        self.positionTicks = JellyfinTicks.ticks(seconds: positionSeconds)
        self.playMethod = "DirectPlay"
        self.canSeek = true
        self.isPaused = isPaused
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case playMethod = "PlayMethod"
        case canSeek = "CanSeek"
        case isPaused = "IsPaused"
    }
}

nonisolated enum JellyfinPlaybackEvent: Equatable, Sendable {
    case start
    case progress
    case stopped

    var path: String {
        switch self {
        case .start: "/Sessions/Playing"
        case .progress: "/Sessions/Playing/Progress"
        case .stopped: "/Sessions/Playing/Stopped"
        }
    }
}
