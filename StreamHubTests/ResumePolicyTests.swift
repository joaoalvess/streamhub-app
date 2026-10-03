import Foundation
import Testing
@testable import StreamHub

struct ResumePolicyTests {

    @Test func positionsUnderTheMinimumStartFromTheBeginning() {
        #expect(ResumePolicy.startSeconds(position: nil, runtimeMinutes: 100) == nil)
        #expect(ResumePolicy.startSeconds(position: 0, runtimeMinutes: 100) == nil)
        #expect(ResumePolicy.startSeconds(position: 29, runtimeMinutes: 100) == nil)
        #expect(ResumePolicy.startSeconds(position: 30, runtimeMinutes: 100) == 30)
    }

    @Test func positionsNearTheEndStartFromTheBeginning() {
        #expect(ResumePolicy.startSeconds(position: 5700, runtimeMinutes: 100) == 5700)
        #expect(ResumePolicy.startSeconds(position: 5701, runtimeMinutes: 100) == nil)
    }

    @Test func unknownRuntimeKeepsThePosition() {
        #expect(ResumePolicy.startSeconds(position: 9000, runtimeMinutes: nil) == 9000)
        #expect(ResumePolicy.startSeconds(position: 9000, runtimeMinutes: 0) == 9000)
    }
}
