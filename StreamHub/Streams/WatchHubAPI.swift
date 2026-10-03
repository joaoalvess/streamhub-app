import Foundation

nonisolated struct WatchHubStream: Decodable, Sendable {
    let name: String?
    let tvOsUrl: String?
}

nonisolated struct WatchHubAPI {
    nonisolated private struct Response: Decodable, Sendable {
        let streams: [WatchHubStream]
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streams(type: String, id: String) async throws -> [WatchHubStream] {
        guard let url = URL(string: "https://watchhub.strem.io/stream/\(type)/\(id).json") else {
            throw StreamsAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            return try await HTTP.fetch(Response.self, for: request, session: session).streams
        } catch let failure as HTTPFailure {
            switch failure {
            case .status(let code, _): throw StreamsAPIError.badStatus(code)
            case .transport(let error): throw StreamsAPIError.transport(error)
            case .decoding(let error): throw StreamsAPIError.decoding(error)
            }
        }
    }
}
