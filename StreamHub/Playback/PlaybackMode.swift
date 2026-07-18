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
}
