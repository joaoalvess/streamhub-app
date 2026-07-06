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
    let baseProvider: () -> URL?

    init(
        session: URLSession = .shared,
        gate: RequestGate = .shared,
        baseProvider: @escaping () -> URL? = { SecretsStore.shared.aioStreamsBase }
    ) {
        self.session = session
        self.gate = gate
        self.baseProvider = baseProvider
    }

    func movieStreams(imdbId: String) async throws -> [AddonStream] {
        guard let base = baseProvider() else { throw StreamsAPIError.notConfigured }
        guard let url = URL(string: base.absoluteString + "/stream/movie/\(imdbId).json") else {
            throw StreamsAPIError.invalidURL
        }
        return try await fetch(url, attempt: 0).streams
    }

    private func fetch(_ url: URL, attempt: Int) async throws -> StreamsResponse {
        await gate.admit()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StreamsAPIError.transport(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                let retryAfter = Self.retryDelay(from: http)
                guard attempt < 2 else {
                    throw StreamsAPIError.rateLimited(retryAfter: retryAfter)
                }
                let delay = (retryAfter ?? Double(attempt + 1) * 1.5) + Double.random(in: 0...0.5)
                try? await Task.sleep(for: .seconds(delay))
                return try await fetch(url, attempt: attempt + 1)
            }
            guard (200...299).contains(http.statusCode) else {
                throw StreamsAPIError.badStatus(http.statusCode)
            }
        }
        do {
            return try JSONDecoder().decode(StreamsResponse.self, from: data)
        } catch {
            throw StreamsAPIError.decoding(error)
        }
    }

    private static func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        let header = response.value(forHTTPHeaderField: "Retry-After")
            ?? response.value(forHTTPHeaderField: "ratelimit-reset")
        return header.flatMap(TimeInterval.init)
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

    func admit() async {
        while true {
            let now = clock.now
            admissions.removeAll { now - $0 >= window }
            if admissions.count < limit {
                admissions.append(now)
                return
            }
            guard let oldest = admissions.first else { continue }
            try? await clock.sleep(until: oldest + window)
        }
    }
}
