import CoreGraphics
import Foundation
import ImageIO
import TVServices

nonisolated enum TopShelfArtwork {
    private static let scrimAlpha: CGFloat = 70.0 / 255.0
    private static let logoMaxWidthRatio: CGFloat = 700.0 / 1280.0
    private static let logoMaxHeightRatio: CGFloat = 260.0 / 720.0
    private static let jpegQuality = 0.85

    @concurrent
    static func prepare(_ snapshot: TopShelfSnapshot, in directory: URL? = TopShelfStorage.artworkDirectory()) async {
        guard let directory,
              (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return
        }
        let size = TVTopShelfSectionedContent.imageSize(for: .hdtv)
        let width = Int(size.width * 2)
        let height = Int(size.height * 2)
        var wroteArtwork = false
        for item in snapshot.items {
            guard !Task.isCancelled else { return }
            guard TopShelfStorage.existingArtworkURL(for: item, in: directory) == nil,
                  let name = TopShelfStorage.artworkFileName(for: item),
                  let imageURL = item.imageURL,
                  let logoURL = item.logoURL else { continue }
            async let backdropImage = image(at: imageURL, maxPixelSize: max(width, height))
            async let logoImage = image(at: logoURL, maxPixelSize: max(width, height))
            guard let backdrop = await backdropImage,
                  let logo = await logoImage,
                  let artwork = render(backdrop: backdrop, logo: logo, width: width, height: height),
                  let data = jpegData(artwork) else { continue }
            try? data.write(to: directory.appending(path: name), options: .atomic)
            wroteArtwork = true
        }
        guard !Task.isCancelled else { return }
        removeStaleArtwork(in: directory, keeping: snapshot)
        if wroteArtwork {
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    static func render(backdrop: CGImage, logo: CGImage, width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(backdrop, in: aspectFill(CGSize(width: backdrop.width, height: backdrop.height), in: canvas))
        context.setFillColor(CGColor(gray: 0, alpha: scrimAlpha))
        context.fill(canvas)
        let logoBounds = CGSize(width: canvas.width * logoMaxWidthRatio, height: canvas.height * logoMaxHeightRatio)
        context.draw(logo, in: aspectFit(CGSize(width: logo.width, height: logo.height), within: logoBounds, centeredIn: canvas))
        return context.makeImage()
    }

    static func staleArtwork(_ names: [String], keeping snapshot: TopShelfSnapshot) -> [String] {
        let expected = Set(snapshot.items.compactMap(TopShelfStorage.artworkFileName(for:)))
        return names.filter { !expected.contains($0) }
    }

    private static func removeStaleArtwork(in directory: URL, keeping snapshot: TopShelfSnapshot) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in staleArtwork(names, keeping: snapshot) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    private static func image(at url: URL, maxPixelSize: Int) async -> CGImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        return centered(CGSize(width: size.width * scale, height: size.height * scale), in: rect)
    }

    private static func aspectFit(_ size: CGSize, within bounds: CGSize, centeredIn rect: CGRect) -> CGRect {
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return centered(CGSize(width: size.width * scale, height: size.height * scale), in: rect)
    }

    private static func centered(_ size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }
}
