import SwiftUI

struct ImdbRatingLabel: View {
    let rating: String

    var body: some View {
        HStack(spacing: 8) {
            Text("IMDb")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: 0xF5C518), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(rating)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
