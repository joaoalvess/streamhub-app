import Foundation
import Testing
@testable import StreamHub

enum StubReply: Sendable {
    case status(Int, Data)
    case failure(URLError.Code)

    static func json(_ body: String, status: Int = 200) -> StubReply {
        .status(status, Data(body.utf8))
    }
}

final class StubRoutes: @unchecked Sendable {
    private struct Route {
        var replies: [StubReply]
        var isHeld: Bool
        var pending: [() -> Void] = []
        var requests: [URL] = []
    }

    private let lock = NSLock()
    private var routes: [String: Route] = [:]

    func register(_ key: String, replies: [StubReply], held: Bool = false) {
        lock.withLock {
            routes[key] = Route(replies: replies, isHeld: held)
        }
    }

    func requests(for key: String) -> [URL] {
        lock.withLock { routes[key]?.requests ?? [] }
    }

    func release(_ key: String) {
        let pending = lock.withLock { () -> [() -> Void] in
            guard var route = routes[key] else { return [] }
            let queued = route.pending
            route.isHeld = false
            route.pending = []
            routes[key] = route
            return queued
        }
        pending.forEach { $0() }
    }

    func remove(_ key: String) {
        let pending = lock.withLock { () -> [() -> Void] in
            routes.removeValue(forKey: key)?.pending ?? []
        }
        pending.forEach { $0() }
    }

    func handle(_ url: URL, deliver: @escaping (StubReply) -> Void) {
        let immediate = lock.withLock { () -> StubReply? in
            guard let key = routes.keys.first(where: { url.absoluteString.contains($0) }),
                  var route = routes[key] else {
                return StubReply.failure(.unsupportedURL)
            }
            route.requests.append(url)
            let reply: StubReply
            if route.replies.count > 1 {
                reply = route.replies.removeFirst()
            } else {
                reply = route.replies.first ?? .failure(.resourceUnavailable)
            }
            if route.isHeld {
                route.pending.append { deliver(reply) }
            }
            routes[key] = route
            return route.isHeld ? nil : reply
        }
        if let immediate {
            deliver(immediate)
        }
    }
}

final class StubURLProtocol: URLProtocol {
    static let routes = StubRoutes()

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.routes.handle(url) { reply in
            self.deliver(reply, for: url)
        }
    }

    override func stopLoading() {}

    private func deliver(_ reply: StubReply, for url: URL) {
        switch reply {
        case .status(let code, let body):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }
}

@MainActor
func pollUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Suite(.serialized)
struct HTTPTests {

    private struct Payload: Decodable, Equatable, Sendable {
        let title: String
        let year: Int
    }

    private struct Endpoint {
        let key: String
        let request: URLRequest
        let session: URLSession

        init(_ replies: StubReply...) throws {
            let key = UUID().uuidString.lowercased()
            let url = try #require(URL(string: "https://stub.test/\(key)/payload.json"))
            self.key = key
            request = URLRequest(url: url)
            session = StubURLProtocol.makeSession()
            StubURLProtocol.routes.register(key, replies: replies)
        }

        func tearDown() {
            StubURLProtocol.routes.remove(key)
            session.invalidateAndCancel()
        }
    }

    private static let payloadJSON = #"{"title":"Um Sonho de Liberdade","year":1994}"#

    @Test(arguments: [200, 201])
    func successfulStatusReturnsBodyAndResponse(code: Int) async throws {
        let endpoint = try Endpoint(.json(Self.payloadJSON, status: code))
        defer { endpoint.tearDown() }

        let (data, response) = try await HTTP.data(for: endpoint.request, session: endpoint.session)

        #expect(data == Data(Self.payloadJSON.utf8))
        #expect(response?.statusCode == code)
    }

    @Test(arguments: [404, 500])
    func nonSuccessStatusBecomesStatusFailure(code: Int) async throws {
        let endpoint = try Endpoint(.json(#"{"error":"falhou"}"#, status: code))
        defer { endpoint.tearDown() }

        let failure = await #expect(throws: HTTPFailure.self) {
            try await HTTP.data(for: endpoint.request, session: endpoint.session)
        }

        guard case .status(let status, let response) = failure else {
            Issue.record("esperava HTTPFailure.status, veio \(String(describing: failure))")
            return
        }
        #expect(status == code)
        #expect(response.statusCode == code)
    }

    @Test func transportErrorIsWrapped() async throws {
        let endpoint = try Endpoint(.failure(.notConnectedToInternet))
        defer { endpoint.tearDown() }

        let failure = await #expect(throws: HTTPFailure.self) {
            try await HTTP.data(for: endpoint.request, session: endpoint.session)
        }

        guard case .transport(let error) = failure else {
            Issue.record("esperava HTTPFailure.transport, veio \(String(describing: failure))")
            return
        }
        #expect((error as? URLError)?.code == .notConnectedToInternet)
    }

    @Test func cancelledRequestBecomesCancellationError() async throws {
        let endpoint = try Endpoint(.failure(.cancelled))
        defer { endpoint.tearDown() }

        await #expect(throws: CancellationError.self) {
            try await HTTP.data(for: endpoint.request, session: endpoint.session)
        }
    }

    @Test func fetchDecodesSuccessfulPayload() async throws {
        let endpoint = try Endpoint(.json(Self.payloadJSON))
        defer { endpoint.tearDown() }

        let payload = try await HTTP.fetch(Payload.self, for: endpoint.request, session: endpoint.session)

        #expect(payload == Payload(title: "Um Sonho de Liberdade", year: 1994))
    }

    @Test func fetchReportsInvalidJSONAsDecodingFailure() async throws {
        let endpoint = try Endpoint(.json("not json"))
        defer { endpoint.tearDown() }

        let failure = await #expect(throws: HTTPFailure.self) {
            try await HTTP.fetch(Payload.self, for: endpoint.request, session: endpoint.session)
        }

        guard case .decoding(let error) = failure else {
            Issue.record("esperava HTTPFailure.decoding, veio \(String(describing: failure))")
            return
        }
        #expect(error is DecodingError)
    }

    @Test func fetchChecksStatusBeforeDecoding() async throws {
        let endpoint = try Endpoint(.json(Self.payloadJSON, status: 500))
        defer { endpoint.tearDown() }

        let failure = await #expect(throws: HTTPFailure.self) {
            try await HTTP.fetch(Payload.self, for: endpoint.request, session: endpoint.session)
        }

        guard case .status(500, _) = failure else {
            Issue.record("esperava HTTPFailure.status(500), veio \(String(describing: failure))")
            return
        }
    }

    @Test func decodeReturnsTheValue() throws {
        let payload = try HTTP.decode(Payload.self, from: Data(Self.payloadJSON.utf8))
        #expect(payload == Payload(title: "Um Sonho de Liberdade", year: 1994))
    }

    @Test func decodeWrapsDecodingErrors() {
        let failure = #expect(throws: HTTPFailure.self) {
            try HTTP.decode(Payload.self, from: Data(#"{"title":"Sem ano"}"#.utf8))
        }

        guard case .decoding(let error) = failure else {
            Issue.record("esperava HTTPFailure.decoding, veio \(String(describing: failure))")
            return
        }
        #expect(error is DecodingError)
    }

    @Test func isCancellationRecognizesCancelledErrors() {
        #expect(HTTP.isCancellation(CancellationError()))
        #expect(HTTP.isCancellation(URLError(.cancelled)))
        #expect(!HTTP.isCancellation(URLError(.timedOut)))
        #expect(!HTTP.isCancellation(HTTPFailure.transport(URLError(.notConnectedToInternet))))
    }

    @Test func isCancellationTreatsAnyErrorAsCancelledInsideACancelledTask() async {
        let task = Task {
            try? await Task.sleep(for: .seconds(30))
            return HTTP.isCancellation(URLError(.timedOut))
        }
        task.cancel()

        #expect(await task.value)
    }
}
