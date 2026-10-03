import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageSize {
    static let poster = 800
    static let wide = 800
    static let backdrop = 1920
    static let logo = 520
}

nonisolated final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private nonisolated final class Entry {
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    private let session: URLSession
    private let memory = NSCache<NSString, Entry>()
    private let lock = NSLock()
    private var inFlight: [NSString: Task<CGImage?, Never>] = [:]

    init(memoryCostLimit: Int = 120 * 1024 * 1024, diskCapacity: Int = 256 * 1024 * 1024) {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: diskCapacity)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
        memory.totalCostLimit = memoryCostLimit
        memory.countLimit = 200
    }

    func cachedImage(for url: URL, maxPixelSize: Int) -> CGImage? {
        lock.withLock { memory.object(forKey: Self.key(url, maxPixelSize))?.image }
    }

    @concurrent
    func image(for url: URL, maxPixelSize: Int) async -> CGImage? {
        await task(for: url, maxPixelSize: maxPixelSize).value
    }

    func prefetch(_ urls: [URL], maxPixelSize: Int) {
        for url in urls {
            _ = task(for: url, maxPixelSize: maxPixelSize)
        }
    }

    private func task(for url: URL, maxPixelSize: Int) -> Task<CGImage?, Never> {
        let key = Self.key(url, maxPixelSize)
        return lock.withLock {
            if let cached = memory.object(forKey: key) {
                let image = cached.image
                return Task { image }
            }
            if let existing = inFlight[key] { return existing }
            let session = session
            let created = Task.detached(priority: .userInitiated) { [weak self] () -> CGImage? in
                let image = await Self.load(url, maxPixelSize: maxPixelSize, session: session)
                self?.finish(key: key, image: image)
                return image
            }
            inFlight[key] = created
            return created
        }
    }

    private func finish(key: NSString, image: CGImage?) {
        lock.withLock {
            inFlight[key] = nil
            guard let image else { return }
            memory.setObject(Entry(image), forKey: key, cost: image.bytesPerRow * image.height)
        }
    }

    private static func key(_ url: URL, _ maxPixelSize: Int) -> NSString {
        "\(maxPixelSize)|\(url.absoluteString)" as NSString
    }

    private static func load(_ url: URL, maxPixelSize: Int, session: URLSession) async -> CGImage? {
        let request = URLRequest(url: url)
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            session.configuration.urlCache?.removeCachedResponse(for: request)
            return nil
        }
        guard let image = downsample(data, maxPixelSize: maxPixelSize) else {
            session.configuration.urlCache?.removeCachedResponse(for: request)
            return nil
        }
        return image
    }

    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
