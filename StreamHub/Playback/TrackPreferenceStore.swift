import Foundation

nonisolated struct TrackPreference: Codable, Equatable, Sendable {
    var audio: String?
    var subtitle: String?
    var subtitlesOff: Bool?

    var preferredAudioLanguages: [String] {
        audio.map { [$0] } ?? []
    }

    var preferredSubtitleLanguages: [String] {
        subtitle.map { [$0] } ?? []
    }

    var subtitlesEnabled: Bool {
        subtitlesOff != true
    }

    var hasSubtitleChoice: Bool {
        subtitle != nil || subtitlesOff != nil
    }

    func applying(_ choice: TrackChoice) -> TrackPreference {
        var result = self
        switch choice {
        case .audio(let language):
            result.audio = language
        case .subtitle(let language):
            result.subtitle = language ?? subtitle
            result.subtitlesOff = false
        case .subtitlesOff:
            result.subtitlesOff = true
        }
        return result
    }

    func overriding(_ fallback: TrackPreference) -> TrackPreference {
        TrackPreference(
            audio: audio ?? fallback.audio,
            subtitle: hasSubtitleChoice ? subtitle : fallback.subtitle,
            subtitlesOff: hasSubtitleChoice ? subtitlesOff : fallback.subtitlesOff
        )
    }
}

nonisolated enum TrackPreferenceScope: Equatable, Sendable {
    case global
    case series(String)
}

nonisolated enum TrackChoice: Equatable, Sendable {
    case audio(String)
    case subtitle(String?)
    case subtitlesOff
}

final class TrackPreferenceStore {
    private nonisolated struct Stored: Codable {
        var global = TrackPreference()
        var perSeries: [String: TrackPreference] = [:]
    }

    private static let baseKey = "trackprefs.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func preference(for scope: TrackPreferenceScope, profileID: UUID?) -> TrackPreference {
        let stored = load(profileID: profileID)
        guard case .series(let seriesKey) = scope, let series = stored.perSeries[seriesKey] else {
            return stored.global
        }
        return series.overriding(stored.global)
    }

    func record(_ choice: TrackChoice, scope: TrackPreferenceScope, profileID: UUID?) {
        var stored = load(profileID: profileID)
        stored.global = stored.global.applying(choice)
        if case .series(let seriesKey) = scope {
            stored.perSeries[seriesKey] = (stored.perSeries[seriesKey] ?? TrackPreference()).applying(choice)
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key(for: profileID))
    }

    private func load(profileID: UUID?) -> Stored {
        guard let data = defaults.data(forKey: Self.key(for: profileID)) else { return Stored() }
        return (try? JSONDecoder().decode(Stored.self, from: data)) ?? Stored()
    }

    private static func key(for profileID: UUID?) -> String {
        guard let profileID else { return baseKey }
        return "\(baseKey).\(profileID.uuidString)"
    }
}
