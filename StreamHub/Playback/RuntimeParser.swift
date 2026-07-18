import Foundation

nonisolated enum RuntimeParser {
    static func minutes(from runtime: String?) -> Int? {
        guard let runtime = runtime?.lowercased() else { return nil }
        if let match = runtime.firstMatch(of: #/(\d+)\s*h\s*(\d+)?/#) {
            let hours = Int(match.1) ?? 0
            let minutes = match.2.flatMap { Int($0) } ?? 0
            return hours * 60 + minutes
        }
        guard let match = runtime.firstMatch(of: #/(\d+)/#) else { return nil }
        return Int(match.1)
    }
}
