import CryptoKit
import Foundation
import UIKit

nonisolated struct JellyfinContext: Sendable {
    let baseURL: URL
    let token: String
    let userId: String
    let authorizationHeader: String
}

nonisolated struct JellyfinLoginBody: Encodable, Sendable {
    let username: String
    let pw: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

actor JellyfinSession {
    static let shared = JellyfinSession()

    private let secrets: SecretsStore
    private let session: URLSession
    private var cached: JellyfinContext?

    init(secrets: SecretsStore = .shared, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    func context() async throws -> JellyfinContext {
        if let cached { return cached }
        guard let base = secrets.jellyfinBase,
              let username = secrets.jellyfinUsername,
              let pw = secrets.jellyfinPw else {
            throw JellyfinError.notConfigured
        }
        let deviceId = await resolvedDeviceId(username: username)
        if let token = secrets.read(.jellyfinAccessToken),
           let userId = secrets.read(.jellyfinUserId) {
            let context = Self.makeContext(base: base, token: token, userId: userId, deviceId: deviceId)
            cached = context
            return context
        }
        return try await login(base: base, username: username, pw: pw, deviceId: deviceId)
    }

    func invalidate() {
        cached = nil
        secrets.remove(.jellyfinAccessToken)
        secrets.remove(.jellyfinUserId)
    }

    private func login(base: URL, username: String, pw: String, deviceId: String) async throws -> JellyfinContext {
        guard let url = URL(string: base.absoluteString + "/Users/AuthenticateByName") else {
            throw JellyfinError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            Self.authorizationHeader(token: nil, deviceId: deviceId, version: Self.appVersion),
            forHTTPHeaderField: "Authorization"
        )
        do {
            request.httpBody = try JSONEncoder().encode(JellyfinLoginBody(username: username, pw: pw))
        } catch {
            throw JellyfinError.decoding(error)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw JellyfinError.transport(error)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                throw JellyfinError.unauthorized
            }
            guard (200...299).contains(http.statusCode) else {
                throw JellyfinError.badStatus(http.statusCode)
            }
        }
        let result: JellyfinAuthResult
        do {
            result = try JSONDecoder().decode(JellyfinAuthResult.self, from: data)
        } catch {
            throw JellyfinError.decoding(error)
        }
        secrets.write(result.accessToken, for: .jellyfinAccessToken)
        secrets.write(result.user.id, for: .jellyfinUserId)
        let context = Self.makeContext(base: base, token: result.accessToken, userId: result.user.id, deviceId: deviceId)
        cached = context
        return context
    }

    private func resolvedDeviceId(username: String) async -> String {
        if let stored = secrets.read(.jellyfinDeviceId) {
            return stored
        }
        let vendorId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        let derived = Self.deviceId(vendorId: vendorId ?? UUID().uuidString, username: username)
        secrets.write(derived, for: .jellyfinDeviceId)
        return derived
    }

    nonisolated static func deviceId(vendorId: String, username: String) -> String {
        let digest = SHA256.hash(data: Data(username.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(vendorId)-\(suffix)"
    }

    nonisolated static func authorizationHeader(token: String?, deviceId: String, version: String) -> String {
        var fields = [
            ("Client", "StreamHub"),
            ("Device", "Apple TV"),
            ("DeviceId", deviceId),
            ("Version", version)
        ]
        if let token {
            fields.append(("Token", token))
        }
        let joined = fields
            .map { "\($0.0)=\"\(encoded($0.1))\"" }
            .joined(separator: ", ")
        return "MediaBrowser " + joined
    }

    nonisolated private static func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    nonisolated private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    nonisolated private static func makeContext(base: URL, token: String, userId: String, deviceId: String) -> JellyfinContext {
        JellyfinContext(
            baseURL: base,
            token: token,
            userId: userId,
            authorizationHeader: authorizationHeader(token: token, deviceId: deviceId, version: appVersion)
        )
    }
}
