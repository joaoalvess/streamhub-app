import Foundation

enum MetadataAPIError: Error, Sendable {
    case invalidURL
    case badStatus(Int)
    case transport(any Error)
    case decoding(any Error)
}

struct MetadataAPI: Sendable {
    static let baseString =
        "https://aiometadata.elfhosted.com/stremio/b11959c7-94fd-4fd2-aa24-6655c4fd7164"

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

    private func get<T: Decodable>(_ type: T.Type, at path: String) async throws -> T {
        let base = SecretsStore.shared.metadataBase?.absoluteString ?? Self.baseString
        guard let url = URL(string: base + "/" + path) else {
            throw MetadataAPIError.invalidURL
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw MetadataAPIError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MetadataAPIError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MetadataAPIError.decoding(error)
        }
    }
}
