import Foundation

nonisolated struct WatchHubStream: Decodable, Sendable {
    let name: String?
    let tvOsUrl: String?
}

nonisolated struct WatchHubAPI {
    private struct Response: Decodable {
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
            let (data, _) = try await HTTP.data(for: request, session: session)
            return try HTTP.decode(Response.self, from: data).streams
        } catch let failure as HTTPFailure {
            switch failure {
            case .status(let code, _): throw StreamsAPIError.badStatus(code)
            case .transport(let error): throw StreamsAPIError.transport(error)
            case .decoding(let error): throw StreamsAPIError.decoding(error)
            }
        }
    }
}
