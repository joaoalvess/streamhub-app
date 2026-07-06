import UIKit

nonisolated struct InfusePlayItem {
    let videoURL: URL
    let filename: String?
    let positionSeconds: Int?
}

nonisolated enum InfuseURLBuilder {
    static let successCallback = "streamhub://infuse/success"
    static let errorCallback = "streamhub://infuse/error"

    static func playURL(
        item: InfusePlayItem,
        success: String? = successCallback,
        error: String? = errorCallback
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"

        var queryItems = [URLQueryItem(name: "url", value: item.videoURL.absoluteString)]
        if let position = item.positionSeconds {
            queryItems.append(URLQueryItem(name: "position", value: String(position)))
        }
        if let filename = item.filename {
            queryItems.append(URLQueryItem(name: "filename", value: filename))
        }
        if let success {
            queryItems.append(URLQueryItem(name: "x-success", value: success))
        }
        if let error {
            queryItems.append(URLQueryItem(name: "x-error", value: error))
        }
        components.queryItems = queryItems

        if let encoded = components.percentEncodedQuery {
            components.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
        }
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
