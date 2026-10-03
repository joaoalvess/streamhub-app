import Foundation

nonisolated enum ProgressBadge: Equatable, Sendable {
    case none
    case inProgress(Double)
    case watched
}
