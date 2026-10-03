import Foundation

nonisolated struct MediaQuality: Hashable, Sendable {
    nonisolated enum Resolution: Int, Comparable, Sendable {
        case sd
        case hd
        case fullHD
        case uhd

        init?(height: Int) {
            guard height > 0 else { return nil }
            if height >= 2000 {
                self = .uhd
            } else if height >= 1000 {
                self = .fullHD
            } else if height >= 690 {
                self = .hd
            } else {
                self = .sd
            }
        }

        init?(width: Int) {
            guard width > 0 else { return nil }
            if width >= 3200 {
                self = .uhd
            } else if width >= 1800 {
                self = .fullHD
            } else if width >= 1200 {
                self = .hd
            } else {
                self = .sd
            }
        }

        init?(width: Int?, height: Int?) {
            let candidates = [height.flatMap(Resolution.init(height:)), width.flatMap(Resolution.init(width:))]
            guard let best = candidates.compactMap({ $0 }).max() else { return nil }
            self = best
        }

        var label: String {
            switch self {
            case .sd: "SD"
            case .hd: "720p"
            case .fullHD: "1080p"
            case .uhd: "4K"
            }
        }

        static func < (lhs: Resolution, rhs: Resolution) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    nonisolated enum DynamicRange: Hashable, Sendable {
        case dolbyVision
        case hdr10Plus
        case hdr10
        case hlg
    }

    nonisolated enum AudioFormat: Hashable, Sendable {
        case atmos
        case trueHD
        case dtsX
        case dtsHD
        case dts
        case dolbyDigitalPlus
        case dolbyDigital
    }

    nonisolated enum Channels: Int, Comparable, Sendable {
        case surround51
        case surround71

        init?(count: Int) {
            if count >= 8 {
                self = .surround71
            } else if count >= 6 {
                self = .surround51
            } else {
                return nil
            }
        }

        var label: String {
            switch self {
            case .surround51: "5.1"
            case .surround71: "7.1"
            }
        }

        static func < (lhs: Channels, rhs: Channels) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var resolution: Resolution?
    var dynamicRange: Set<DynamicRange>
    var audio: Set<AudioFormat>
    var channels: Channels?
    var hasPortugueseSubtitles: Bool
    var hasClosedCaptions: Bool
    var hasAudioDescription: Bool

    init(
        resolution: Resolution? = nil,
        dynamicRange: Set<DynamicRange> = [],
        audio: Set<AudioFormat> = [],
        channels: Channels? = nil,
        hasPortugueseSubtitles: Bool = false,
        hasClosedCaptions: Bool = false,
        hasAudioDescription: Bool = false
    ) {
        self.resolution = resolution
        self.dynamicRange = dynamicRange
        self.audio = audio
        self.channels = channels
        self.hasPortugueseSubtitles = hasPortugueseSubtitles
        self.hasClosedCaptions = hasClosedCaptions
        self.hasAudioDescription = hasAudioDescription
    }

    var dynamicRangeBadge: String? {
        if dynamicRange.contains(.dolbyVision) { return "Dolby Vision" }
        if dynamicRange.contains(.hdr10Plus) { return "HDR10+" }
        if dynamicRange.contains(.hdr10) || dynamicRange.contains(.hlg) { return "HDR" }
        return nil
    }

    var badges: [String] {
        var badges: [String] = []
        if resolution == .uhd { badges.append("4K") }
        if let dynamicRangeBadge { badges.append(dynamicRangeBadge) }
        if audio.contains(.atmos) { badges.append("Dolby Atmos") }
        if let channels { badges.append(channels.label) }
        if hasPortugueseSubtitles { badges.append("LEG") }
        if hasClosedCaptions { badges.append("CC") }
        if hasAudioDescription { badges.append("AD") }
        return badges
    }

    var compactBadges: [String] {
        var badges: [String] = []
        if let resolution { badges.append(resolution.label) }
        if dynamicRange.contains(.dolbyVision) {
            badges.append("DV")
        } else if !dynamicRange.isEmpty {
            badges.append("HDR")
        }
        return badges
    }
}
