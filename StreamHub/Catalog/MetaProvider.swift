import Foundation
import Observation

@Observable
final class MetaProvider {
    private let api: MetadataAPI
    private let cache = AsyncTTLCache<String, MetaDetail?>(ttl: 600, capacity: 30)

    init(api: MetadataAPI = MetadataAPI()) {
        self.api = api
    }

    func detail(for item: MediaItem) async throws -> MetaDetail? {
        guard let request = Self.metaRequest(for: item) else { return nil }
        let api = self.api
        return try await cache.value(for: "\(request.type)|\(request.id)") {
            try await api.meta(type: request.type, id: request.id)
        }
    }

    nonisolated static func metaRequest(for item: MediaItem) -> (type: String, id: String)? {
        guard let id = item.contentId ?? item.imdbId else { return nil }
        let type = item.kind == .series || item.isAnime ? "series" : "movie"
        return (type, id)
    }
}
