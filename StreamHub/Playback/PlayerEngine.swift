import Foundation

nonisolated enum PlayerEngine: String, CaseIterable, Hashable {
    case native
    case infuse

    var icon: String {
        switch self {
        case .native: "play.rectangle.fill"
        case .infuse: "flame.fill"
        }
    }

    var next: PlayerEngine {
        self == .native ? .infuse : .native
    }

    static func stored(in defaults: UserDefaults = .standard) -> PlayerEngine {
        defaults.string(forKey: storageKey).flatMap(PlayerEngine.init(rawValue:)) ?? .infuse
    }

    func store(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }

    private static let storageKey = "playerEngine"
}
