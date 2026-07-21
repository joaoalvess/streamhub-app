import Foundation

nonisolated enum JellyfinError: Error {
    case notConfigured
    case unauthorized
    case badStatus(Int)
    case transport(any Error)
    case decoding(any Error)
}

nonisolated struct JellyfinAPI {
    let session: URLSession
    let auth: JellyfinSession

    init(session: URLSession = .shared, auth: JellyfinSession = .shared) {
        self.session = session
        self.auth = auth
    }

    func userViews() async throws -> [JellyfinItem] {
        try await withAuthRetry { context in
            let result: JellyfinQueryResult = try await get(
                path: "/UserViews",
                query: [URLQueryItem(name: "userId", value: context.userId)],
                context: context
            )
            return result.items
        }
    }

    func resumeItems(limit: Int) async throws -> [JellyfinItem] {
        try await withAuthRetry { context in
            let result: JellyfinQueryResult = try await get(
                path: "/UserItems/Resume",
                query: [
                    URLQueryItem(name: "userId", value: context.userId),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "mediaTypes", value: "Video")
                ],
                context: context
            )
            return result.items
        }
    }

    func latestItems(limit: Int) async throws -> [JellyfinItem] {
        try await withAuthRetry { context in
            try await get(
                path: "/Items/Latest",
                query: [
                    URLQueryItem(name: "userId", value: context.userId),
                    URLQueryItem(name: "limit", value: String(limit))
                ],
                context: context
            )
        }
    }

    func items(parentId: String, limit: Int) async throws -> [JellyfinItem] {
        try await withAuthRetry { context in
            let result: JellyfinQueryResult = try await get(
                path: "/Items",
                query: [
                    URLQueryItem(name: "userId", value: context.userId),
                    URLQueryItem(name: "parentId", value: parentId),
                    URLQueryItem(name: "recursive", value: "true"),
                    URLQueryItem(name: "mediaTypes", value: "Video"),
                    URLQueryItem(name: "sortBy", value: "DateCreated"),
                    URLQueryItem(name: "sortOrder", value: "Descending"),
                    URLQueryItem(name: "startIndex", value: "0"),
                    URLQueryItem(name: "limit", value: String(limit))
                ],
                context: context
            )
            return result.items
        }
    }

    func streamURL(itemId: String) async throws -> URL {
        let context = try await auth.context()
        guard let url = Self.streamURL(base: context.baseURL, itemId: itemId, token: context.token) else {
            throw JellyfinError.notConfigured
        }
        return url
    }

    func report(_ event: JellyfinPlaybackEvent, body: JellyfinPlaybackReport) async throws {
        try await withAuthRetry { context in
            guard let url = Self.url(base: context.baseURL, path: event.path, query: []) else {
                throw JellyfinError.notConfigured
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(context.authorizationHeader, forHTTPHeaderField: "Authorization")
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw JellyfinError.decoding(error)
            }
            let (_, response) = try await send(request)
            try Self.validate(response)
        }
    }

    nonisolated static func url(base: URL, path: String, query: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(string: base.absoluteString + path) else { return nil }
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    nonisolated static func streamURL(base: URL, itemId: String, token: String) -> URL? {
        url(base: base, path: "/Videos/\(itemId)/stream", query: [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: itemId),
            URLQueryItem(name: "api_key", value: token)
        ])
    }

    nonisolated static func primaryImageURL(base: URL, itemId: String, tag: String, maxWidth: Int) -> URL? {
        url(base: base, path: "/Items/\(itemId)/Images/Primary", query: [
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90")
        ])
    }

    nonisolated static func backdropImageURL(base: URL, itemId: String, tag: String, maxWidth: Int) -> URL? {
        url(base: base, path: "/Items/\(itemId)/Images/Backdrop/0", query: [
            URLQueryItem(name: "tag", value: tag),
            URLQueryItem(name: "maxWidth", value: String(maxWidth)),
            URLQueryItem(name: "quality", value: "90")
        ])
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem], context: JellyfinContext) async throws -> T {
        guard let url = Self.url(base: context.baseURL, path: path, query: query) else {
            throw JellyfinError.notConfigured
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(context.authorizationHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await send(request)
        try Self.validate(response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JellyfinError.decoding(error)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw JellyfinError.transport(error)
        }
    }

    nonisolated private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            throw JellyfinError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw JellyfinError.badStatus(http.statusCode)
        }
    }

    private func withAuthRetry<T>(_ operation: (JellyfinContext) async throws -> T) async throws -> T {
        let context = try await auth.context()
        do {
            return try await operation(context)
        } catch JellyfinError.unauthorized {
            await auth.invalidate()
            let fresh = try await auth.context()
            return try await operation(fresh)
        }
    }
}
