import Foundation
import Testing
@testable import StreamHub

@MainActor
struct AsyncTTLCacheTests {

    private final class ManualClock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private final class LoadCounter {
        var calls = 0
    }

    private struct LoadFailure: Error {}

    private func counting<Value>(
        _ counter: LoadCounter,
        returning value: Value,
        after delay: Duration = .zero
    ) -> () async throws -> Value {
        {
            counter.calls += 1
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            return value
        }
    }

    @Test func returnsCachedValueWithinTTL() async throws {
        let clock = ManualClock()
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int>(ttl: 60, capacity: 10, now: { clock.now })
        let first = try await cache.value(for: "a", load: counting(counter, returning: 1))
        clock.now += 59
        let second = try await cache.value(for: "a", load: counting(counter, returning: 2))
        #expect(first == 1)
        #expect(second == 1)
        #expect(counter.calls == 1)
    }

    @Test func reloadsAfterTTLExpires() async throws {
        let clock = ManualClock()
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int>(ttl: 60, capacity: 10, now: { clock.now })
        _ = try await cache.value(for: "a", load: counting(counter, returning: 1))
        clock.now += 60
        let refreshed = try await cache.value(for: "a", load: counting(counter, returning: 2))
        #expect(refreshed == 2)
        #expect(counter.calls == 2)
    }

    @Test func evictsLeastRecentlyUsedBeyondCapacity() async throws {
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, String>(ttl: 60, capacity: 2)
        _ = try await cache.value(for: "a", load: counting(counter, returning: "a"))
        _ = try await cache.value(for: "b", load: counting(counter, returning: "b"))
        _ = try await cache.value(for: "a", load: counting(counter, returning: "a"))
        _ = try await cache.value(for: "c", load: counting(counter, returning: "c"))
        #expect(counter.calls == 3)
        _ = try await cache.value(for: "a", load: counting(counter, returning: "a"))
        _ = try await cache.value(for: "c", load: counting(counter, returning: "c"))
        #expect(counter.calls == 3)
        _ = try await cache.value(for: "b", load: counting(counter, returning: "b"))
        #expect(counter.calls == 4)
    }

    @Test func concurrentCallersShareOneLoad() async throws {
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int>(ttl: 60, capacity: 10)
        var callers: [Task<Int, any Error>] = []
        for _ in 0..<5 {
            callers.append(Task {
                try await cache.value(for: "k", load: counting(counter, returning: 42, after: .milliseconds(50)))
            })
        }
        var values: [Int] = []
        for caller in callers {
            values.append(try await caller.value)
        }
        #expect(values == [42, 42, 42, 42, 42])
        #expect(counter.calls == 1)
    }

    @Test func cancellingOneCallerKeepsSharedLoad() async throws {
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int>(ttl: 60, capacity: 10)
        let first = Task {
            try await cache.value(for: "k", load: counting(counter, returning: 9, after: .milliseconds(50)))
        }
        let second = Task {
            try await cache.value(for: "k", load: counting(counter, returning: 0))
        }
        first.cancel()
        #expect(try await second.value == 9)
        #expect(counter.calls == 1)
    }

    @Test func failedLoadIsNotCached() async throws {
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int>(ttl: 60, capacity: 10)
        await #expect(throws: LoadFailure.self) {
            try await cache.value(for: "a") {
                counter.calls += 1
                throw LoadFailure()
            }
        }
        let recovered = try await cache.value(for: "a", load: counting(counter, returning: 5))
        #expect(recovered == 5)
        #expect(counter.calls == 2)
    }

    @Test func cachesNilValues() async throws {
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int?>(ttl: 60, capacity: 10)
        let first = try await cache.value(for: "a", load: counting(counter, returning: Int?.none))
        let second = try await cache.value(for: "a", load: counting(counter, returning: Int?.some(1)))
        #expect(first == nil)
        #expect(second == nil)
        #expect(counter.calls == 1)
    }

    @Test func removeAllForcesReload() async throws {
        let counter = LoadCounter()
        let cache = AsyncTTLCache<String, Int>(ttl: 60, capacity: 10)
        _ = try await cache.value(for: "a", load: counting(counter, returning: 1))
        cache.removeAll()
        let reloaded = try await cache.value(for: "a", load: counting(counter, returning: 2))
        #expect(reloaded == 2)
        #expect(counter.calls == 2)
    }
}
