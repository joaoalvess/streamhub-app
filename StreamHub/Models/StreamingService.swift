import Foundation

nonisolated enum StreamingService: String, CaseIterable, Hashable {
    case netflix = "nfx"
    case disneyPlus = "dnp"
    case hboMax = "hbm"
    case primeVideo = "amp"
    case appleTVPlus = "atp"
    case globoplay = "gop"
    case crunchyroll = "cru"
    case paramountPlus = "pmp"
    case hulu = "hlu"
    case discoveryPlus = "dpe"
    case claroVideo = "clv"

    init?(catalogId: String) {
        let prefix = "streaming."
        guard catalogId.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(catalogId.dropFirst(prefix.count)))
    }

    var displayName: String {
        switch self {
        case .netflix: "Netflix"
        case .disneyPlus: "Disney+"
        case .hboMax: "HBO Max"
        case .primeVideo: "Prime Video"
        case .appleTVPlus: "Apple TV+"
        case .globoplay: "Globoplay"
        case .crunchyroll: "Crunchyroll"
        case .paramountPlus: "Paramount+"
        case .hulu: "Hulu"
        case .discoveryPlus: "Discovery+"
        case .claroVideo: "Claro Video"
        }
    }

    var badgeLabel: String { displayName }

    var isSubscribed: Bool {
        switch self {
        case .netflix, .disneyPlus, .hboMax, .primeVideo, .appleTVPlus, .globoplay: true
        default: false
        }
    }

    var playCTA: String {
        switch self {
        case .netflix, .hboMax: "Reproduzir na \(displayName)"
        default: "Reproduzir no \(displayName)"
        }
    }

    var appURLs: [URL] {
        let schemes: [String]
        switch self {
        case .netflix: schemes = ["nflx://"]
        case .disneyPlus: schemes = ["disneyplus://"]
        case .hboMax: schemes = ["hbomax://", "max://"]
        case .primeVideo: schemes = ["aiv://", "primevideo://"]
        case .appleTVPlus: schemes = ["com.apple.tv://"]
        case .globoplay: schemes = ["globoplay://"]
        default: schemes = []
        }
        return schemes.compactMap(URL.init(string:))
    }

    var watchHubNames: [String] {
        switch self {
        case .netflix: ["Netflix"]
        case .disneyPlus: ["Disney Plus"]
        case .hboMax: ["HBO Max", "HBO Max Amazon Channel"]
        case .primeVideo: ["Amazon Prime Video", "Amazon Video"]
        case .appleTVPlus: ["Apple TV Plus", "Apple TV+"]
        case .globoplay: ["Globoplay"]
        default: []
        }
    }
}
