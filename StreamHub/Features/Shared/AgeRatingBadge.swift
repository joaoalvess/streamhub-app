import SwiftUI

struct AgeRatingBadge: View {
    let rating: MediaItem.AgeRating

    var body: some View {
        Text(rating.label)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 24)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(rating.color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
