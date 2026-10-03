import Foundation

nonisolated enum JellyfinSegmentMapper {
    static func skipSegments(from segments: [JellyfinMediaSegment]) -> [NativeSkipSegment] {
        segments
            .compactMap(skipSegment)
            .sorted { $0.start < $1.start }
    }

    private static func skipSegment(_ segment: JellyfinMediaSegment) -> NativeSkipSegment? {
        guard let kind = skipKind(for: segment.type),
              let startTicks = segment.startTicks,
              let endTicks = segment.endTicks,
              startTicks >= 0,
              endTicks > startTicks
        else { return nil }
        return NativeSkipSegment(start: seconds(ticks: startTicks), end: seconds(ticks: endTicks), kind: kind)
    }

    private static func skipKind(for type: String?) -> NativeSkipSegment.Kind? {
        switch (type ?? "").lowercased() {
        case "intro": .intro
        case "outro": .credits
        case "recap": .recap
        case "preview": .preview
        default: nil
        }
    }

    private static func seconds(ticks: Int64) -> Double {
        Double(ticks) / Double(JellyfinTicks.perSecond)
    }
}
