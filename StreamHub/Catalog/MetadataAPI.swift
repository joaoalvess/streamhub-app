import Foundation

nonisolated enum MetadataAPIError: Error, Sendable {
    case invalidURL
    case badStatus(Int)
    case transport(any Error)
    case decoding(any Error)
}

nonisolated struct MetadataAPI: Sendable {
    static let baseString =
        "https://aiometadata.elfhosted.com/stremio/b11959c7-94fd-4fd2-aa24-6655c4fd7164"

    private static let resolvedBase: String = {
        let base = SecretsStore.shared.metadataBase?.absoluteString ?? baseString
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }()

    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func manifest(tag: String? = nil) async throws -> AddonManifest {
        var path = "manifest.json"
        if let tag { path += "?tag=\(tag)" }
        return try await get(AddonManifest.self, at: path)
    }

    func catalog(type: String, id: String, skip: Int = 0) async throws -> [MetaPreview] {
        var path = "catalog/\(type)/\(id)"
        if skip > 0 { path += "/skip=\(skip)" }
        path += ".json"
        return try await get(CatalogResponse.self, at: path).metas
    }

    func meta(type: String, id: String) async throws -> MetaDetail? {
        try await get(MetaResponse.self, at: "meta/\(type)/\(id).json").meta
    }

    func search(type: String, id: String, query: String) async throws -> [MetaPreview] {
        guard let path = Self.searchPath(type: type, id: id, query: query) else {
            throw MetadataAPIError.invalidURL
        }
        return try await get(CatalogResponse.self, at: path).metas
    }

    static func searchPath(type: String, id: String, query: String) -> String? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: searchValueAllowed) else {
            return nil
        }
        return "catalog/\(type)/\(id)/search=\(encoded).json"
    }

    private static let searchValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    @concurrent
    private func get<T: Decodable & Sendable>(_ type: T.Type, at path: String) async throws -> T {
        guard let url = URL(string: Self.resolvedBase + "/" + path) else {
            throw MetadataAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, _) = try await HTTP.data(for: request, session: session)
            return try HTTP.decode(T.self, from: data)
        } catch let failure as HTTPFailure {
            switch failure {
            case .status(let code, _): throw MetadataAPIError.badStatus(code)
            case .transport(let error): throw MetadataAPIError.transport(error)
            case .decoding(let error): throw MetadataAPIError.decoding(error)
            }
        }
    }
}
