import SwiftUI

struct MediaProgressBar: View {
    let progress: Double

    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.progressTrack)
                Capsule()
                    .fill(Theme.progressFill)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
