import Foundation

struct StreamsResponse: Decodable, Sendable {
    let streams: [AddonStream]
}

struct AddonStream: Decodable, Sendable {
    let name: String?
    let description: String?
    let url: String?
    let externalUrl: String?
    let behaviorHints: StreamBehaviorHints?
    let streamData: StreamDataTag?

    var isPlayable: Bool {
        guard streamData?.type != "statistic",
              let url,
              let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

struct StreamBehaviorHints: Decodable, Sendable {
    let bingeGroup: String?
    let videoHash: String?
    let videoSize: Int64?
    let filename: String?

    private enum CodingKeys: String, CodingKey {
        case bingeGroup, videoHash, videoSize, filename
    }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            bingeGroup = nil
            videoHash = nil
            videoSize = nil
            filename = nil
            return
        }
        bingeGroup = (try? container.decodeIfPresent(String.self, forKey: .bingeGroup)) ?? nil
        videoHash = (try? container.decodeIfPresent(String.self, forKey: .videoHash)) ?? nil
        if let whole = (try? container.decodeIfPresent(Int64.self, forKey: .videoSize)) ?? nil {
            videoSize = whole
        } else if let fractional = (try? container.decodeIfPresent(Double.self, forKey: .videoSize)) ?? nil {
            videoSize = Int64(fractional)
        } else {
            videoSize = nil
        }
        filename = (try? container.decodeIfPresent(String.self, forKey: .filename)) ?? nil
    }
}

struct StreamDataTag: Decodable, Sendable {
    let type: String?

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            type = nil
            return
        }
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? nil
    }
}
