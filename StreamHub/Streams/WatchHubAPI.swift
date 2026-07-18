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
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw StreamsAPIError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data).streams
    }
}
