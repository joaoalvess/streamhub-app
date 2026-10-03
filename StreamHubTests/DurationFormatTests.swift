import Foundation
import Testing
@testable import StreamHub

struct DurationFormatTests {

    @Test func underAnHourShowsMinutes() {
        #expect(DurationFormat.label(minutes: 0) == "0 min")
        #expect(DurationFormat.label(minutes: 45) == "45 min")
        #expect(DurationFormat.label(minutes: 59) == "59 min")
    }

    @Test func wholeHoursDropMinutes() {
        #expect(DurationFormat.label(minutes: 60) == "1 h")
        #expect(DurationFormat.label(minutes: 120) == "2 h")
    }

    @Test func hoursAndMinutesAreCombined() {
        #expect(DurationFormat.label(minutes: 61) == "1 h 1 min")
        #expect(DurationFormat.label(minutes: 150) == "2 h 30 min")
    }

    @Test func negativeMinutesClampToZero() {
        #expect(DurationFormat.label(minutes: -5) == "0 min")
    }

    @Test func remainingPrefixesLabel() {
        #expect(DurationFormat.remaining(minutes: 45) == "Restam 45 min")
        #expect(DurationFormat.remaining(minutes: 120) == "Restam 2 h")
        #expect(DurationFormat.remaining(minutes: 150) == "Restam 2 h 30 min")
    }
}
