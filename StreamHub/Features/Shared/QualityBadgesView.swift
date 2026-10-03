import SwiftUI

struct QualityBadgesView: View {
    let badges: [String]

    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: 10) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Theme.textSecondary.opacity(0.5), lineWidth: 1.5)
                        }
                }
            }
        }
    }
}
