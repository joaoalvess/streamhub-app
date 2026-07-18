import Foundation

nonisolated struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var avatarAsset: String?
    var coverAsset: String?
}
