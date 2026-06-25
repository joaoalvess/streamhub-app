import SwiftUI

struct MenuLabel: View {
    let section: MenuSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            switch section.icon {
            case .symbol(let name):
                Image(systemName: name)
            case .asset(let name):
                ChannelBadge(asset: name)
            }
        }
    }
}

struct ChannelBadge: View {
    let asset: String
    var size: CGFloat = 30

    var body: some View {
        Image(asset)
            .resizable()
            .renderingMode(.original)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}
