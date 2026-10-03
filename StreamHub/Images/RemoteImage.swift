import SwiftUI

struct RemoteImage<Placeholder: View>: View {
    private struct Loaded {
        let url: URL
        let image: CGImage
    }

    private let url: URL?
    private let maxPixelSize: Int
    private let contentMode: ContentMode
    private let placeholder: () -> Placeholder

    @State private var loaded: Loaded?

    init(
        url: URL?,
        maxPixelSize: Int,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack {
            if let image = displayedImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private var displayedImage: CGImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize)
    }

    private func load() async {
        guard let url else {
            loaded = nil
            return
        }
        if loaded?.url == url { return }
        if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            loaded = Loaded(url: url, image: cached)
            return
        }
        guard let image = await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize),
              !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            loaded = Loaded(url: url, image: image)
        }
    }
}

extension RemoteImage where Placeholder == Color {
    init(url: URL?, maxPixelSize: Int, contentMode: ContentMode = .fill) {
        self.init(url: url, maxPixelSize: maxPixelSize, contentMode: contentMode) { Color.clear }
    }
}
