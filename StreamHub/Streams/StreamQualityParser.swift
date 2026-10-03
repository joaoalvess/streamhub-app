import Foundation

nonisolated enum StreamQualityParser {
    private static let portugueseFlags: Set<Character> = ["🇧🇷", "🇵🇹"]
    private static let channelSuffix = #"(?:\d(?:\.\d)?)?"#

    static func parse(_ stream: AddonStream) -> MediaQuality {
        parse(
            name: stream.name,
            description: stream.description,
            filename: stream.behaviorHints?.filename,
            bingeGroup: stream.behaviorHints?.bingeGroup
        )
    }

    static func parse(name: String?, description: String?, filename: String?, bingeGroup: String?) -> MediaQuality {
        let sources = [bingeGroup, name, filename.map(technicalPart(of:))].compactMap { $0 }
        let text = sources.joined(separator: " | ")
        return MediaQuality(
            resolution: sources.lazy.compactMap(resolution(in:)).first,
            dynamicRange: dynamicRange(in: text),
            audio: audioFormats(in: text),
            channels: channels(in: text),
            hasPortugueseSubtitles: description.map(hasPortugueseSubtitles(in:)) ?? false
        )
    }

    static func technicalPart(of filename: String) -> String {
        let pattern = #"(?<![\p{L}\p{N}])(?:(?:19|20)\d{2}|s\d{1,2}(?:e\d{1,3})?)(?!\p{N})"#
        var searchStart = filename.startIndex
        while let match = filename.range(
            of: pattern,
            options: [.regularExpression, .caseInsensitive],
            range: searchStart..<filename.endIndex
        ) {
            if match.lowerBound > filename.startIndex {
                return String(filename[match.upperBound...])
            }
            searchStart = match.upperBound
        }
        return filename
    }

    static func resolution(in text: String) -> MediaQuality.Resolution? {
        if let range = tokenRange(#"(?:2160|1440|1080|720|576|480|360)[pi]"#, in: text),
           let lines = Int(text[range].dropLast()) {
            return MediaQuality.Resolution(height: lines)
        }
        if containsToken("4k|uhd", in: text) {
            return .uhd
        }
        return nil
    }

    static func dynamicRange(in text: String) -> Set<MediaQuality.DynamicRange> {
        var ranges: Set<MediaQuality.DynamicRange> = []
        if containsToken(#"dv|dovi|dolby[ ._-]?vision"#, in: text) {
            ranges.insert(.dolbyVision)
        }
        if containsToken(#"hdr10(?:\+|plus)"#, in: text) {
            ranges.insert(.hdr10Plus)
        }
        if containsToken(#"hdr(?:10)?"#, in: text) {
            ranges.insert(.hdr10)
        }
        if containsToken("hlg", in: text) {
            ranges.insert(.hlg)
        }
        return ranges
    }

    static func audioFormats(in text: String) -> Set<MediaQuality.AudioFormat> {
        var formats: Set<MediaQuality.AudioFormat> = []
        if containsToken("atmos", in: text) {
            formats.insert(.atmos)
        }
        if containsToken("truehd" + channelSuffix, in: text) {
            formats.insert(.trueHD)
        }
        if containsToken(#"dts[ .:_-]?x"# + channelSuffix, in: text) {
            formats.insert(.dtsX)
        }
        if containsToken(#"dts[ ._-]?hd(?:[ ._-]?ma)?"# + channelSuffix, in: text) {
            formats.insert(.dtsHD)
        }
        if formats.isDisjoint(with: [.dtsX, .dtsHD]), containsToken("dts" + channelSuffix, in: text) {
            formats.insert(.dts)
        }
        if containsToken(#"(?:ddp|dd\+|e-?ac-?3)"# + channelSuffix, in: text) {
            formats.insert(.dolbyDigitalPlus)
        }
        if containsToken(#"(?:dd(?!\+)|ac-?3)"# + channelSuffix, in: text) {
            formats.insert(.dolbyDigital)
        }
        return formats
    }

    static func channels(in text: String) -> MediaQuality.Channels? {
        if matches(#"(?<!\d)7\.1(?!\d)"#, in: text) || containsToken("8ch", in: text) {
            return .surround71
        }
        if matches(#"(?<!\d)5\.1(?!\d)"#, in: text) || containsToken("6ch", in: text) {
            return .surround51
        }
        return nil
    }

    static func hasPortugueseSubtitles(in description: String) -> Bool {
        description
            .split(whereSeparator: { $0 == "/" || $0.isNewline })
            .contains { segment in
                segment.contains(where: portugueseFlags.contains) && containsToken("subs?", in: String(segment))
            }
    }

    private static func containsToken(_ pattern: String, in text: String) -> Bool {
        tokenRange(pattern, in: text) != nil
    }

    private static func tokenRange(_ pattern: String, in text: String) -> Range<String.Index>? {
        text.range(
            of: #"(?<![\p{L}\p{N}])(?:"# + pattern + #")(?![\p{L}\p{N}])"#,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
