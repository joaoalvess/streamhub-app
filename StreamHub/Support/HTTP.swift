import Foundation

nonisolated enum HTTPFailure: Error {
    case transport(any Error)
    case status(Int, HTTPURLResponse)
    case decoding(any Error)
}

nonisolated enum HTTP {
    static func data(for request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse?) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if isCancellation(error) { throw CancellationError() }
            throw HTTPFailure.transport(error)
        }
        let http = response as? HTTPURLResponse
        if let http, !(200...299).contains(http.statusCode) {
            throw HTTPFailure.status(http.statusCode, http)
        }
        return (data, http)
    }

    @concurrent
    static func fetch<T: Decodable & Sendable>(_ type: T.Type, for request: URLRequest, session: URLSession) async throws -> T {
        let (payload, _) = try await data(for: request, session: session)
        return try decode(T.self, from: payload)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPFailure.decoding(error)
        }
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }
}
