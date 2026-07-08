import UIKit

nonisolated struct InfusePlayItem {
    let videoURL: URL
    let filename: String?
    let positionSeconds: Int?
}

nonisolated enum InfuseURLBuilder {
    static let successCallback = "streamhub://infuse/success"
    static let errorCallback = "streamhub://infuse/error"

    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func playURL(
        item: InfusePlayItem,
        success: String? = successCallback,
        error: String? = errorCallback
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"

        var pairs: [(name: String, value: String)] = [("url", item.videoURL.absoluteString)]
        if let position = item.positionSeconds {
            pairs.append(("position", String(position)))
        }
        if let filename = item.filename {
            pairs.append(("filename", filename))
        }
        if let success {
            pairs.append(("x-success", success))
        }
        if let error {
            pairs.append(("x-error", error))
        }

        var encodedItems: [URLQueryItem] = []
        for pair in pairs {
            guard let encoded = pair.value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) else {
                return nil
            }
            encodedItems.append(URLQueryItem(name: pair.name, value: encoded))
        }
        components.percentEncodedQueryItems = encodedItems
        return components.url
    }
}

nonisolated enum InfuseCallback: Equatable {
    case success(lastPlayedURL: String?, position: Int?)
    case error(code: String?, message: String?, failedURLs: [String])

    init?(url: URL) {
        guard url.scheme == "streamhub",
              url.host() == "infuse",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        switch components.path {
        case "/success":
            self = .success(
                lastPlayedURL: value("lastPlayedUrl"),
                position: value("position").flatMap(Int.init)
            )
        case "/error":
            self = .error(
                code: value("errorCode"),
                message: value("errorMessage"),
                failedURLs: items.filter { $0.name == "failedUrl" }.compactMap(\.value)
            )
        default:
            return nil
        }
    }
}

enum InfuseLauncher {
    private static let probe = URL(string: "infuse://")

    static let isInstalled: Bool = {
        guard let probe else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }()

    static func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }
}
