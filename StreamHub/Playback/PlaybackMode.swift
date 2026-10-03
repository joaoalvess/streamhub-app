import Foundation

nonisolated enum PlaybackMode: String, CaseIterable, Hashable {
    case dubbed
    case subtitled
    case enhanced

    var label: String {
        switch self {
        case .dubbed: "Dub"
        case .subtitled: "Leg"
        case .enhanced: "Best"
        }
    }

    var icon: String {
        switch self {
        case .dubbed: "sofa.fill"
        case .subtitled: "4k.tv.fill"
        case .enhanced: "sparkles"
        }
    }

    var next: PlaybackMode {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .dubbed }
        return all[(index + 1) % all.count]
    }

    var isAvailable: Bool { self != .enhanced }

    private static let baseStorageKey = "playbackMode"

    private static func storageKey(for profileId: UUID?) -> String {
        guard let profileId else { return baseStorageKey }
        return "\(baseStorageKey).\(profileId.uuidString)"
    }

    static func stored(profileId: UUID?, in defaults: UserDefaults = .standard) -> PlaybackMode {
        guard let raw = defaults.string(forKey: storageKey(for: profileId)),
              let mode = PlaybackMode(rawValue: raw),
              mode.isAvailable else { return .dubbed }
        return mode
    }

    func store(profileId: UUID?, in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey(for: profileId))
    }

    static func removeStored(profileId: UUID, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(for: profileId))
    }
}
