import Foundation
import Observation

@Observable
final class MetaProvider {
    private let api: MetadataAPI
    private var cache: [String: (fetchedAt: Date, detail: MetaDetail?)] = [:]
    private var inFlight: [String: Task<MetaDetail?, any Error>] = [:]
    private static let cacheTTL: TimeInterval = 600

    init(api: MetadataAPI = MetadataAPI()) {
        self.api = api
    }

    func detail(for item: MediaItem) async throws -> MetaDetail? {
        guard let request = Self.metaRequest(for: item) else { return nil }
        let key = "\(request.type)|\(request.id)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL {
            return cached.detail
        }
        if let running = inFlight[key] {
            return try await running.value
        }
        let api = self.api
        let task = Task { try await api.meta(type: request.type, id: request.id) }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let detail = try await task.value
        cache[key] = (Date(), detail)
        return detail
    }

    nonisolated static func metaRequest(for item: MediaItem) -> (type: String, id: String)? {
        guard let id = item.contentId ?? item.imdbId else { return nil }
        let type = item.kind == .series || item.isAnime ? "series" : "movie"
        return (type, id)
    }
}
