import Foundation
import Observation

@Observable
final class ProfileStore {
    private static let profilesKey = "profiles.v1"

    private(set) var profiles: [Profile] = []
    private(set) var activeProfileID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load([Profile].self, key: Self.profilesKey, defaults: defaults) ?? []
        profiles = stored.map(Self.sanitized)
    }

    // Descarta referências a assets que não existem mais no catálogo (ex.: set de
    // emojis antigo), caindo no monograma/cover padrão em vez de renderizar em branco.
    private static func sanitized(_ profile: Profile) -> Profile {
        var profile = profile
        if let avatar = profile.avatarAsset, !ProfileImageCatalog.avatars.contains(avatar) {
            profile.avatarAsset = nil
        }
        if let cover = profile.coverAsset, !ProfileImageCatalog.covers.contains(cover) {
            profile.coverAsset = nil
        }
        return profile
    }

    var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    func select(_ profile: Profile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfileID = profile.id
    }

    func deselect() {
        activeProfileID = nil
    }

    func upsert(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = nil
        }
        persist()
    }

    private func persist() {
        Self.save(profiles, key: Self.profilesKey, defaults: defaults)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
