import Foundation

nonisolated enum StreamsAPIError: Error {
    case notConfigured
    case invalidURL
    case badStatus(Int)
    case rateLimited(retryAfter: TimeInterval?)
    case transport(any Error)
    case decoding(any Error)
}

nonisolated struct StreamsAPI {
    let session: URLSession
    let gate: RequestGate
    let baseProvider: (StreamProfile) -> URL?

    init(
        session: URLSession = .shared,
        gate: RequestGate = .shared,
        baseProvider: @escaping (StreamProfile) -> URL? = { SecretsStore.shared.streamsBase(for: $0) }
    ) {
        self.session = session
        self.gate = gate
        self.baseProvider = baseProvider
    }

    func streams(profile: StreamProfile, type: String, id: String) async throws -> [AddonStream] {
        guard let base = baseProvider(profile) else { throw StreamsAPIError.notConfigured }
        guard let url = URL(string: base.absoluteString + "/stream/\(type)/\(id).json") else {
            throw StreamsAPIError.invalidURL
        }
        return try await fetch(url, attempt: 0).streams
    }

    private func fetch(_ url: URL, attempt: Int) async throws -> StreamsResponse {
        try await gate.admit()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            return try await HTTP.fetch(StreamsResponse.self, for: request, session: session)
        } catch HTTPFailure.status(429, let response) {
            let retryAfter = Self.retryDelay(from: response)
            guard attempt < 2 else {
                throw StreamsAPIError.rateLimited(retryAfter: retryAfter)
            }
            let delay = (retryAfter ?? Double(attempt + 1) * 1.5) + Double.random(in: 0...0.5)
            try await Task.sleep(for: .seconds(delay))
            return try await fetch(url, attempt: attempt + 1)
        } catch HTTPFailure.status(let code, _) {
            throw StreamsAPIError.badStatus(code)
        } catch HTTPFailure.transport(let error) {
            throw StreamsAPIError.transport(error)
        } catch HTTPFailure.decoding(let error) {
            throw StreamsAPIError.decoding(error)
        }
    }

    static func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        let header = response.value(forHTTPHeaderField: "Retry-After")
            ?? response.value(forHTTPHeaderField: "ratelimit-reset")
        guard let value = header.flatMap({ TimeInterval($0) }), !value.isNaN else { return nil }
        return min(max(value, 0), 30)
    }
}

actor RequestGate {
    static let shared = RequestGate()

    private let limit: Int
    private let window: Duration
    private let clock = ContinuousClock()
    private var admissions: [ContinuousClock.Instant] = []

    init(limit: Int = 5, window: Duration = .seconds(5)) {
        self.limit = limit
        self.window = window
    }

    func admit() async throws {
        while true {
            try Task.checkCancellation()
            let now = clock.now
            admissions.removeAll { now - $0 >= window }
            if admissions.count < limit {
                admissions.append(now)
                return
            }
            try await clock.sleep(until: (admissions.first ?? now) + window)
        }
    }
}
