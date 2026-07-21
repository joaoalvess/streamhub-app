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

    enum CodingKeys: String, CodingKey {
        case items = "Items"
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

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case userData = "UserData"
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
