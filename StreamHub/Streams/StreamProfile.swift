import Foundation

nonisolated enum StreamProfile: String {
    case cinema
    case casual
    case anime

    init?(mode: PlaybackMode) {
        switch mode {
        case .dubbed: self = .casual
        case .subtitled: self = .cinema
        case .enhanced: return nil
        }
    }
}
