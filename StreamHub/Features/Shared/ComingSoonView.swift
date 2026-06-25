import SwiftUI

struct ComingSoonView: View {
    let title: String
    let icon: MenuIcon

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                iconView

                Text(title)
                    .font(Theme.Font.sectionTitle)
                    .foregroundStyle(Theme.textSecondary)

                Text("Em breve")
                    .font(Theme.Font.meta)
                    .foregroundStyle(Theme.textTertiary)
            }
            .focusable()
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        case .asset(let name):
            ChannelBadge(asset: name, size: 200)
        }
    }
}

#Preview {
    ComingSoonView(title: "Netflix", icon: .asset("logo.netflix"))
}
