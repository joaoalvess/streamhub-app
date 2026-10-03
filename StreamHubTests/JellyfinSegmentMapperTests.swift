import Foundation
import Testing
@testable import StreamHub

struct JellyfinSegmentMapperTests {

    @Test func mapsSupportedTypesToSkipKinds() {
        let segments = JellyfinSegmentMapper.skipSegments(from: [
            segment("Recap", start: 0, end: 600_000_000),
            segment("Intro", start: 600_000_000, end: 1_500_000_000),
            segment("Outro", start: 12_000_000_000, end: 13_200_000_000),
            segment("Preview", start: 13_200_000_000, end: 13_500_000_000)
        ])
        #expect(segments == [
            NativeSkipSegment(start: 0, end: 60, kind: .recap),
            NativeSkipSegment(start: 60, end: 150, kind: .intro),
            NativeSkipSegment(start: 1200, end: 1320, kind: .credits),
            NativeSkipSegment(start: 1320, end: 1350, kind: .preview)
        ])
    }

    @Test func dropsCommercialAnnotationAndUnknownTypes() {
        let segments = JellyfinSegmentMapper.skipSegments(from: [
            segment("Commercial", start: 0, end: 100_000_000),
            segment("Annotation", start: 0, end: 100_000_000),
            segment("SomethingNew", start: 0, end: 100_000_000),
            segment(nil, start: 0, end: 100_000_000)
        ])
        #expect(segments.isEmpty)
    }

    @Test func dropsInvalidRanges() {
        let segments = JellyfinSegmentMapper.skipSegments(from: [
            segment("Intro", start: 100_000_000, end: 100_000_000),
            segment("Intro", start: 200_000_000, end: 100_000_000),
            segment("Intro", start: -10_000_000, end: 100_000_000),
            segment("Intro", start: nil, end: 100_000_000),
            segment("Intro", start: 0, end: nil),
            segment("Outro", start: 10_000_000, end: 20_000_000)
        ])
        #expect(segments == [NativeSkipSegment(start: 1, end: 2, kind: .credits)])
    }

    @Test func sortsByStart() {
        let segments = JellyfinSegmentMapper.skipSegments(from: [
            segment("Outro", start: 12_000_000_000, end: 13_200_000_000),
            segment("Intro", start: 600_000_000, end: 1_500_000_000),
            segment("Recap", start: 0, end: 600_000_000)
        ])
        #expect(segments.map(\.start) == [0, 60, 1200])
    }

    @Test func convertsTicksToFractionalSeconds() {
        let segments = JellyfinSegmentMapper.skipSegments(from: [
            segment("Intro", start: 15_000_000, end: 905_000_000)
        ])
        #expect(segments == [NativeSkipSegment(start: 1.5, end: 90.5, kind: .intro)])
    }

    @Test func emptyListGivesNoSegments() {
        #expect(JellyfinSegmentMapper.skipSegments(from: []).isEmpty)
    }

    @Test func mapsDecodedServerResponse() throws {
        let json = Data(#"""
        {
          "Items": [
            { "Id": "segment-2", "ItemId": "item-1", "Type": "Outro", "StartTicks": 12000000000, "EndTicks": 13200000000 },
            { "Id": "segment-3", "ItemId": "item-1", "Type": "Commercial", "StartTicks": 6000000000, "EndTicks": 6300000000 },
            { "Id": "segment-1", "ItemId": "item-1", "Type": "Intro", "StartTicks": 0, "EndTicks": 900000000 }
          ],
          "TotalRecordCount": 3,
          "StartIndex": 0
        }
        """#.utf8)
        let result = try JSONDecoder().decode(JellyfinMediaSegmentResult.self, from: json)
        #expect(JellyfinSegmentMapper.skipSegments(from: result.items) == [
            NativeSkipSegment(start: 0, end: 90, kind: .intro),
            NativeSkipSegment(start: 1200, end: 1320, kind: .credits)
        ])
    }

    private func segment(_ type: String?, start: Int64?, end: Int64?) -> JellyfinMediaSegment {
        JellyfinMediaSegment(type: type, startTicks: start, endTicks: end)
    }
}
