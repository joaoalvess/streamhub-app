import Foundation
import Security

nonisolated struct SecretsStore {
    static let shared = SecretsStore()

    private static let service = "joaoalvess.StreamHub.secrets"

    nonisolated enum Key: String, CaseIterable {
        case aioStreamsCinemaBase = "AIOStreamsCinemaBase"
        case aioStreamsCasualBase = "AIOStreamsCasualBase"
        case aioStreamsAnimeBase = "AIOStreamsAnimeBase"
        case aioMetadataBase = "AIOMetadataBase"
    }

    func bootstrapIfNeeded() {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let values = plist as? [String: String] else { return }
        for key in Key.allCases {
            guard let value = values[key.rawValue], !value.isEmpty else { continue }
            write(value, for: key)
        }
    }

    func streamsBase(for profile: StreamProfile) -> URL? {
        let key: Key = switch profile {
        case .cinema: .aioStreamsCinemaBase
        case .casual: .aioStreamsCasualBase
        case .anime: .aioStreamsAnimeBase
        }
        guard let value = read(key) else { return nil }
        let normalized = value.hasSuffix("/") ? String(value.dropLast()) : value
        return URL(string: normalized)
    }

    var aioStreamsBase: URL? { streamsBase(for: .cinema) }

    var metadataBase: URL? {
        read(.aioMetadataBase).flatMap(URL.init(string:))
    }

    private func read(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status != errSecSuccess else { return }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
