import Foundation
import Testing
@testable import StreamHub

@MainActor
struct TrackPreferenceStoreTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "TrackPreferenceStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func emptyStoreResolvesNoPreference() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())

        let preference = store.preference(for: .series("tt0903747"), profileID: nil)

        #expect(preference == TrackPreference())
        #expect(preference.preferredAudioLanguages.isEmpty)
        #expect(preference.preferredSubtitleLanguages.isEmpty)
        #expect(preference.subtitlesEnabled)
    }

    @Test func seriesChoiceRecordsSeriesAndGlobal() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())

        store.record(.audio("ja"), scope: .series("tt0903747"), profileID: nil)

        #expect(store.preference(for: .series("tt0903747"), profileID: nil).audio == "ja")
        #expect(store.preference(for: .global, profileID: nil).audio == "ja")
        #expect(store.preference(for: .series("tt0944947"), profileID: nil).audio == "ja")
    }

    @Test func seriesPreferenceWinsOverGlobal() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())
        store.record(.audio("ja"), scope: .series("tt0903747"), profileID: nil)
        store.record(.audio("en"), scope: .global, profileID: nil)

        #expect(store.preference(for: .series("tt0903747"), profileID: nil).audio == "ja")
        #expect(store.preference(for: .global, profileID: nil).audio == "en")
        #expect(store.preference(for: .series("tt0944947"), profileID: nil).audio == "en")
    }

    @Test func globalChoiceDoesNotCreateSeriesPreference() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())
        store.record(.audio("pt"), scope: .global, profileID: nil)
        store.record(.audio("en"), scope: .global, profileID: nil)

        #expect(store.preference(for: .series("tt0903747"), profileID: nil).audio == "en")
    }

    @Test func seriesFallsBackToGlobalPerSlot() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())
        store.record(.subtitle("pt"), scope: .global, profileID: nil)
        store.record(.audio("ja"), scope: .series("tt0903747"), profileID: nil)

        let preference = store.preference(for: .series("tt0903747"), profileID: nil)

        #expect(preference.audio == "ja")
        #expect(preference.subtitle == "pt")
        #expect(preference.subtitlesEnabled)
    }

    @Test func subtitlesOffDisablesSubtitles() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())
        store.record(.subtitle("en"), scope: .series("tt0903747"), profileID: nil)
        store.record(.subtitlesOff, scope: .series("tt0903747"), profileID: nil)

        let preference = store.preference(for: .series("tt0903747"), profileID: nil)

        #expect(preference.subtitlesOff == true)
        #expect(!preference.subtitlesEnabled)
        #expect(preference.preferredSubtitleLanguages == ["en"])
        #expect(!store.preference(for: .global, profileID: nil).subtitlesEnabled)
    }

    @Test func choosingSubtitleAfterOffEnablesIt() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())
        store.record(.subtitlesOff, scope: .global, profileID: nil)
        store.record(.subtitle("es"), scope: .global, profileID: nil)

        let preference = store.preference(for: .global, profileID: nil)

        #expect(preference.subtitlesEnabled)
        #expect(preference.preferredSubtitleLanguages == ["es"])
    }

    @Test func seriesSubtitleOverridesGlobalSubtitlesOff() throws {
        let store = TrackPreferenceStore(defaults: try makeDefaults())
        store.record(.subtitle("en"), scope: .series("tt0903747"), profileID: nil)
        store.record(.subtitlesOff, scope: .global, profileID: nil)

        let series = store.preference(for: .series("tt0903747"), profileID: nil)
        let other = store.preference(for: .series("tt0944947"), profileID: nil)

        #expect(series.subtitlesEnabled)
        #expect(series.preferredSubtitleLanguages == ["en"])
        #expect(!other.subtitlesEnabled)
    }

    @Test func subtitleWithUnknownLanguageKeepsPreviousLanguage() {
        let preference = TrackPreference(subtitle: "pt", subtitlesOff: true).applying(.subtitle(nil))

        #expect(preference.subtitle == "pt")
        #expect(preference.subtitlesOff == false)
    }

    @Test func profilesAreIsolated() throws {
        let defaults = try makeDefaults()
        let store = TrackPreferenceStore(defaults: defaults)
        let first = UUID()
        let second = UUID()

        store.record(.audio("ja"), scope: .series("tt0903747"), profileID: first)

        #expect(store.preference(for: .series("tt0903747"), profileID: first).audio == "ja")
        #expect(store.preference(for: .series("tt0903747"), profileID: second).audio == nil)
        #expect(store.preference(for: .series("tt0903747"), profileID: nil).audio == nil)
        #expect(defaults.data(forKey: "trackprefs.v1.\(first.uuidString)") != nil)
    }

    @Test func preferencesPersistAcrossInstances() throws {
        let defaults = try makeDefaults()
        let profile = UUID()
        TrackPreferenceStore(defaults: defaults).record(.audio("fr"), scope: .series("tt0903747"), profileID: profile)

        let reloaded = TrackPreferenceStore(defaults: defaults)

        #expect(reloaded.preference(for: .series("tt0903747"), profileID: profile).audio == "fr")
        #expect(reloaded.preference(for: .global, profileID: profile).audio == "fr")
    }
}
