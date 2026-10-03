import Foundation

nonisolated enum ResumePolicy {
    static let minimumSeconds = 30
    static let nearEndRatio = 0.95
    static let completionRatio = 0.92

    static func startSeconds(position: Int?, runtimeMinutes: Int?) -> Int? {
        guard let position, position >= minimumSeconds else { return nil }
        if let runtimeMinutes, runtimeMinutes > 0,
           Double(position) > Double(runtimeMinutes * 60) * nearEndRatio {
            return nil
        }
        return position
    }
}
