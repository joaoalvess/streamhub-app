import Foundation
import Testing
@testable import StreamHub

struct JellyfinModelsTests {

    @Test func decodesAuthenticationResult() throws {
        let json = Data(#"""
        {
          "User": { "Id": "a08200e4a7074525a96cd4c795a1fd08", "Name": "someone" },
          "SessionInfo": { "Id": "session-1" },
          "AccessToken": "abc123def456",
          "ServerId": "server-1"
        }
        """#.utf8)
        let result = try JSONDecoder().decode(JellyfinAuthResult.self, from: json)
        #expect(result.accessToken == "abc123def456")
        #expect(result.user.id == "a08200e4a7074525a96cd4c795a1fd08")
    }

    @Test func decodesQueryResultWithFullItem() throws {
        let json = Data(#"""
        {
          "Items": [
            {
              "Id": "0cf38f82040e9100203e8c817b44a4d5",
              "Name": "Akame ga Kill - S01E23",
              "Type": "Movie",
              "ProductionYear": 2014,
              "RunTimeTicks": 14210900000,
              "ImageTags": { "Primary": "tag-primary" },
              "BackdropImageTags": ["tag-backdrop"],
              "UserData": {
                "PlaybackPositionTicks": 901370000,
                "PlayedPercentage": 6.32,
                "Played": false
              }
            }
          ],
          "TotalRecordCount": 1,
          "StartIndex": 0
        }
        """#.utf8)
        let result = try JSONDecoder().decode(JellyfinQueryResult.self, from: json)
        let item = try #require(result.items.first)
        #expect(item.id == "0cf38f82040e9100203e8c817b44a4d5")
        #expect(item.name == "Akame ga Kill - S01E23")
        #expect(item.primaryImageTag == "tag-primary")
        #expect(item.backdropImageTag == "tag-backdrop")
        #expect(item.runtimeMinutes == 23)
        #expect(item.positionSeconds == 90)
        #expect(item.userData?.played == false)
    }

    @Test func decodesLatestArrayAndItemWithoutOptionalFields() throws {
        let json = Data(#"""
        [
          { "Id": "item-1", "Name": "Elementary.S05E24", "Type": "Movie" }
        ]
        """#.utf8)
        let items = try JSONDecoder().decode([JellyfinItem].self, from: json)
        let item = try #require(items.first)
        #expect(item.primaryImageTag == nil)
        #expect(item.backdropImageTag == nil)
        #expect(item.runtimeMinutes == nil)
        #expect(item.positionSeconds == nil)
        #expect(item.productionYear == nil)
    }

    @Test func decodesMediaStreamsAndTotalCount() throws {
        let json = Data(#"""
        {
          "Items": [
            {
              "Id": "item-1",
              "Name": "Some Movie",
              "Type": "Movie",
              "MediaStreams": [
                { "Type": "Video", "Codec": "hevc", "Height": 2160 },
                { "Type": "Audio", "Codec": "eac3", "Language": "por" },
                { "Type": "Subtitle", "Codec": "ass", "Language": "por" }
              ]
            }
          ],
          "TotalRecordCount": 1240,
          "StartIndex": 100
        }
        """#.utf8)
        let result = try JSONDecoder().decode(JellyfinQueryResult.self, from: json)
        #expect(result.totalRecordCount == 1240)
        let item = try #require(result.items.first)
        let streams = try #require(item.mediaStreams)
        #expect(streams.count == 3)
        #expect(streams[0].type == "Video")
        #expect(streams[0].height == 2160)
        #expect(streams[1].language == "por")
        #expect(streams[2].type == "Subtitle")
    }

    @Test func convertsTicksBothWays() {
        #expect(JellyfinTicks.seconds(901_370_000) == 90)
        #expect(JellyfinTicks.ticks(seconds: 90) == 900_000_000)
        #expect(JellyfinTicks.seconds(JellyfinTicks.ticks(seconds: 8166)) == 8166)
    }

    @Test func encodesPlaybackReportBody() throws {
        let report = JellyfinPlaybackReport(itemId: "item-1", playSessionId: "ps-1", positionSeconds: 90)
        let data = try JSONEncoder().encode(report)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["ItemId"] as? String == "item-1")
        #expect(object["PlaySessionId"] as? String == "ps-1")
        #expect(object["PositionTicks"] as? Int64 == 900_000_000)
        #expect(object["PlayMethod"] as? String == "DirectPlay")
        #expect(object["CanSeek"] as? Bool == true)
        #expect(object["IsPaused"] as? Bool == false)
    }

    @Test func stoppedReportOmitsPauseFlag() throws {
        let report = JellyfinPlaybackReport(itemId: "item-1", playSessionId: "ps-1", positionSeconds: 30, isPaused: nil)
        let data = try JSONEncoder().encode(report)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["IsPaused"] == nil)
    }
}
