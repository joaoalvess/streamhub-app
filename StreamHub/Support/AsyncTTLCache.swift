import Foundation

final class AsyncTTLCache<Key: Hashable, Value: Sendable> {
    private struct Entry {
        let value: Value
        let storedAt: Date
        var lastAccess: Int
    }

    private let ttl: TimeInterval
    private let capacity: Int
    private let now: () -> Date
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Value, any Error>] = [:]
    private var accessCount = 0

    init(ttl: TimeInterval, capacity: Int, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.capacity = capacity
        self.now = now
    }

    func value(for key: Key, load: @escaping () async throws -> Value) async throws -> Value {
        if let entry = entries[key] {
            if isFresh(entry, at: now()) {
                entries[key]?.lastAccess = nextAccess()
                return entry.value
            }
            entries[key] = nil
        }
        if let running = inFlight[key] {
            return try await running.value
        }
        let task = Task { try await load() }
        inFlight[key] = task
        let result = await task.result
        if inFlight[key] == task {
            inFlight[key] = nil
            if case .success(let value) = result {
                store(value, for: key)
            }
        }
        return try result.get()
    }

    func removeAll() {
        entries.removeAll()
        inFlight.removeAll()
    }

    private func store(_ value: Value, for key: Key) {
        let date = now()
        entries = entries.filter { isFresh($0.value, at: date) }
        entries[key] = Entry(value: value, storedAt: date, lastAccess: nextAccess())
        while entries.count > capacity,
              let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            entries[oldest] = nil
        }
    }

    private func isFresh(_ entry: Entry, at date: Date) -> Bool {
        date.timeIntervalSince(entry.storedAt) < ttl
    }

    private func nextAccess() -> Int {
        accessCount += 1
        return accessCount
    }
}
