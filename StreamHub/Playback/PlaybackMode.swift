import Foundation

enum PlaybackMode: String, CaseIterable, Hashable {
    case dubbed
    case subtitled
    case enhanced

    var label: String {
        switch self {
        case .dubbed: "Dublado"
        case .subtitled: "Legendado"
        case .enhanced: "Enhanced"
        }
    }

    var isAvailable: Bool { self != .enhanced }
}
