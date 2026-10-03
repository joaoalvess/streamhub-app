import CryptoKit
import Foundation

nonisolated struct TopShelfSnapshot: Codable, Equatable, Sendable {
    nonisolated struct Item: Codable, Equatable, Sendable {
        let contentID: String
        let title: String
        let imageURL: URL?
        let logoURL: URL?
        let progress: Double?
    }

    let profileID: UUID
    let items: [Item]
}

nonisolated struct TopShelfLink: Equatable, Sendable {
    nonisolated enum Action: String, Sendable {
        case display
        case play
    }

    private static let scheme = "streamhub"
    private static let host = "topshelf"
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    let action: Action
    let profileID: UUID
    let contentID: String

    init(action: Action, profileID: UUID, contentID: String) {
        self.action = action
        self.profileID = profileID
        self.contentID = contentID
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              url.host() == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let action = Action(rawValue: String(components.path.dropFirst())) else {
            return nil
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let profileID = value("profile").flatMap(UUID.init(uuidString:)),
              let contentID = value("content"), !contentID.isEmpty else {
            return nil
        }
        self.init(action: action, profileID: profileID, contentID: contentID)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/\(action.rawValue)"
        let pairs = [("profile", profileID.uuidString), ("content", contentID)]
        var encodedItems: [URLQueryItem] = []
        for (name, value) in pairs {
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) else {
                return nil
            }
            encodedItems.append(URLQueryItem(name: name, value: encoded))
        }
        components.percentEncodedQueryItems = encodedItems
        return components.url
    }
}

nonisolated enum TopShelfStorage {
    static let snapshotKey = "topshelf.snapshot.v1"
    private static let artworkPath = "Library/Caches/TopShelf"

    static func appGroupIdentifier(bundleIdentifier: String, isExtension: Bool) -> String? {
        let parts = bundleIdentifier.split(separator: ".")
        let appParts = isExtension ? parts.dropLast() : parts[...]
        guard !appParts.isEmpty else { return nil }
        return "group." + appParts.joined(separator: ".")
    }

    static func sharedDefaults(bundle: Bundle = .main) -> UserDefaults? {
        guard let group = appGroupIdentifier(bundle: bundle), sharedContainer(group: group) != nil else {
            return nil
        }
        return UserDefaults(suiteName: group)
    }

    static func artworkDirectory(bundle: Bundle = .main) -> URL? {
        guard let group = appGroupIdentifier(bundle: bundle) else { return nil }
        return sharedContainer(group: group)?.appending(path: artworkPath, directoryHint: .isDirectory)
    }

    static func artworkFileName(for item: TopShelfSnapshot.Item) -> String? {
        guard let imageURL = item.imageURL, let logoURL = item.logoURL else { return nil }
        let key = [item.contentID, imageURL.absoluteString, logoURL.absoluteString].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    static func existingArtworkURL(for item: TopShelfSnapshot.Item, in directory: URL) -> URL? {
        guard let name = artworkFileName(for: item) else { return nil }
        let url = directory.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private static func appGroupIdentifier(bundle: Bundle) -> String? {
        guard let bundleIdentifier = bundle.bundleIdentifier else { return nil }
        return appGroupIdentifier(bundleIdentifier: bundleIdentifier, isExtension: bundle.bundleURL.pathExtension == "appex")
    }

    private static func sharedContainer(group: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func load(from defaults: UserDefaults) -> TopShelfSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    static func save(_ snapshot: TopShelfSnapshot, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}
