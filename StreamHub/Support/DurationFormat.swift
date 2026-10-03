import Foundation

nonisolated enum DurationFormat {
    static func label(minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let rest = total % 60
        guard hours > 0 else { return "\(total) min" }
        guard rest > 0 else { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    static func remaining(minutes: Int) -> String {
        "Restam " + label(minutes: minutes)
    }
}
