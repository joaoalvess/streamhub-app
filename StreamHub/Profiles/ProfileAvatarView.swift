import SwiftUI

struct ProfileAvatarView: View {
    let name: String
    let avatarAsset: String?
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            if let avatarAsset {
                Image(avatarAsset)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFill()
            } else {
                MonogramPalette.color(for: name)
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

nonisolated enum MonogramPalette {
    static let colors: [Color] = [
        Color(hex: 0x8E5A3A), Color(hex: 0x3A6E8E), Color(hex: 0x5A8E3A),
        Color(hex: 0x7A3A8E), Color(hex: 0x8E3A55), Color(hex: 0x3A8E7F)
    ]

    static func color(for name: String) -> Color {
        guard !colors.isEmpty else { return Color(hex: 0x15130F) }
        let sum = name.unicodeScalars.reduce(UInt(0)) { $0 &+ UInt($1.value) }
        return colors[Int(sum % UInt(colors.count))]
    }
}

#Preview {
    HStack(spacing: 32) {
        ProfileAvatarView(name: "João Alves", avatarAsset: nil, size: 120)
        ProfileAvatarView(name: "Maria", avatarAsset: nil, size: 120)
        ProfileAvatarView(name: "", avatarAsset: nil, size: 120)
    }
    .padding(80)
    .background(Theme.bg)
}
