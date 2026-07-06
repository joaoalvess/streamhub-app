import Foundation

nonisolated struct StreamCandidate {
    let videoURL: URL
    let filename: String?
    let matchText: String
    let resolution: Int
    let isCached: Bool
    let hasPTAudio: Bool
    let hasOriginalAudio: Bool
    let isDualAudio: Bool
    let hdrScore: Int
    let sizeBytes: Int64
    let seeds: Int

    init?(stream: AddonStream) {
        guard stream.isPlayable,
              let urlString = stream.url,
              let url = URL(string: urlString) else { return nil }

        let name = stream.name ?? ""
        let description = stream.description ?? ""
        let hints = stream.behaviorHints
        let nameLines = name.split(separator: "\n").map(String.init)
        let bingeFields = (hints?.bingeGroup ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        videoURL = url
        filename = hints?.filename
        matchText = hints?.filename ?? description
        isCached = nameLines.first?.range(of: "^\\[[A-Z0-9]+\\+\\]", options: .regularExpression) != nil
        resolution = Self.resolution(bingeFields: bingeFields, name: name)

        let audio = Self.audio(description: description, bingeFields: bingeFields)
        hasPTAudio = audio.pt
        hasOriginalAudio = audio.original
        isDualAudio = audio.dual

        hdrScore = Self.hdrScore(nameLines: nameLines, bingeFields: bingeFields)
        sizeBytes = hints?.videoSize ?? Self.sizeBytes(description: description)
        seeds = Self.seeds(description: description)
    }

    private static func resolution(bingeFields: [String], name: String) -> Int {
        for field in bingeFields {
            guard field.range(of: "^\\d{3,4}p$", options: .regularExpression) != nil,
                  let value = Int(field.dropLast()) else { continue }
            return value
        }
        let lowered = name.lowercased()
        if lowered.contains("2160p") || lowered.contains("4k") { return 2160 }
        for value in [1440, 1080, 720, 576, 480] where lowered.contains("\(value)p") {
            return value
        }
        return 0
    }

    private static func audio(description: String, bingeFields: [String])
        -> (pt: Bool, original: Bool, dual: Bool) {
        var pt = false
        var original = false
        var dual = false
        let languageLine = description
            .split(separator: "\n")
            .map(String.init)
            .last { Self.containsFlag($0) || $0.localizedCaseInsensitiveContains("dual audio") }
        if let languageLine {
            let tokens = languageLine
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            for token in tokens {
                if token.localizedCaseInsensitiveContains("dual audio") {
                    dual = true
                    pt = true
                    original = true
                    continue
                }
                guard !token.localizedCaseInsensitiveContains("subs") else { continue }
                if token.contains("🇧🇷") || token.contains("🇵🇹") {
                    pt = true
                } else if Self.containsFlag(token) {
                    original = true
                }
            }
        }
        if bingeFields.contains(where: { $0.caseInsensitiveCompare("Portuguese") == .orderedSame }) {
            pt = true
        }
        return (pt, original, dual)
    }

    private static func containsFlag(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x1F1E6...0x1F1FF).contains($0.value) }
    }

    private static func hdrScore(nameLines: [String], bingeFields: [String]) -> Int {
        var tokens = Set(bingeFields.map { $0.uppercased() })
        for line in nameLines.dropFirst() {
            for token in line.split(separator: "|") {
                tokens.insert(token.trimmingCharacters(in: .whitespaces).uppercased())
            }
        }
        var score = 0
        if tokens.contains("DV") || tokens.contains("DOLBY VISION") { score += 4 }
        if tokens.contains(where: { $0.hasPrefix("HDR") }) { score += 2 }
        if tokens.contains("10BIT") || tokens.contains("10-BIT") { score += 1 }
        return score
    }

    private static func sizeBytes(description: String) -> Int64 {
        guard let match = description.firstMatch(of: #/💾\s*([0-9.,]+)\s*(GiB|GB|MiB|MB)/#) else {
            return 0
        }
        let number = Double(match.1.replacingOccurrences(of: ",", with: ".")) ?? 0
        let multiplier: Double
        switch String(match.2) {
        case "GiB": multiplier = 1_073_741_824
        case "GB": multiplier = 1_000_000_000
        case "MiB": multiplier = 1_048_576
        default: multiplier = 1_000_000
        }
        return Int64(number * multiplier)
    }

    private static func seeds(description: String) -> Int {
        guard let match = description.firstMatch(of: #/👤\s*(\d+)/#) else { return 0 }
        return Int(match.1) ?? 0
    }
}
