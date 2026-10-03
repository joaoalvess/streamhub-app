import Foundation

nonisolated enum JellyfinError: Error {
    case notConfigured
    case unauthorized
    case badStatus(Int)
    case transport(any Error)
    case decoding(any Error)

    init(_ failure: HTTPFailure) {
        switch failure {
        case .transport(let error): self = .transport(error)
        case .status(401, _): self = .unauthorized
        case .status(let code, _): self = .badStatus(code)
        case .decoding(let error): self = .decoding(error)
        }
    }
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
                    URLQueryItem(name: "mediaTypes", value: "Video"),
                    URLQueryItem(name: "fields", value: "MediaStreams")
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
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "fields", value: "MediaStreams")
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
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "fields", value: "MediaStreams")
                ],
                context: context
            )
            return result.items
        }
    }

    func search(term: String, limit: Int) async throws -> [JellyfinItem] {
        try await withAuthRetry { context in
            let result: JellyfinQueryResult = try await get(
                path: "/Items",
                query: Self.searchQuery(userId: context.userId, term: term, limit: limit),
                context: context
            )
            return result.items
        }
    }

    func allItems(startIndex: Int, limit: Int) async throws -> (items: [JellyfinItem], total: Int) {
        try await withAuthRetry { context in
            let result: JellyfinQueryResult = try await get(
                path: "/Items",
                query: Self.pageQuery(userId: context.userId, startIndex: startIndex, limit: limit),
                context: context
            )
            return (result.items, result.totalRecordCount ?? result.items.count)
        }
    }

    func mediaSegments(itemId: String) async throws -> [JellyfinMediaSegment] {
        try await withAuthRetry { context in
            let result: JellyfinMediaSegmentResult = try await get(
                path: Self.mediaSegmentsPath(itemId: itemId),
                query: [],
                context: context
            )
            return result.items
        }
    }

    nonisolated static func searchQuery(userId: String, term: String, limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "searchTerm", value: term),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "mediaTypes", value: "Video"),
            URLQueryItem(name: "sortBy", value: "SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "MediaStreams")
        ]
    }

    nonisolated static func pageQuery(userId: String, startIndex: Int, limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "recursive", value: "true"),
            URLQueryItem(name: "mediaTypes", value: "Video"),
            URLQueryItem(name: "sortBy", value: "SortName"),
            URLQueryItem(name: "sortOrder", value: "Ascending"),
            URLQueryItem(name: "startIndex", value: String(startIndex)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "MediaStreams")
        ]
    }

    nonisolated static func mediaSegmentsPath(itemId: String) -> String {
        "/MediaSegments/\(itemId)"
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
            _ = try await send(request)
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

    private func get<T: Decodable & Sendable>(path: String, query: [URLQueryItem], context: JellyfinContext) async throws -> T {
        guard let url = Self.url(base: context.baseURL, path: path, query: query) else {
            throw JellyfinError.notConfigured
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(context.authorizationHeader, forHTTPHeaderField: "Authorization")
        do {
            return try await HTTP.fetch(T.self, for: request, session: session)
        } catch let failure as HTTPFailure {
            throw JellyfinError(failure)
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            return try await HTTP.data(for: request, session: session).0
        } catch let failure as HTTPFailure {
            throw JellyfinError(failure)
        }
    }

    private func withAuthRetry<T>(_ operation: (JellyfinContext) async throws -> T) async throws -> T {
        let context = try await auth.context()
        do {
            return try await operation(context)
        } catch JellyfinError.unauthorized {
            await auth.invalidate(ifToken: context.token)
            let fresh = try await auth.context()
            return try await operation(fresh)
        }
    }
}
