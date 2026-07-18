import SwiftUI

struct SidebarProfileHeader: View {
    @Environment(ProfileStore.self) private var profileStore
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            profileStore.deselect()
        } label: {
            HStack(spacing: isFocused ? 21 : 12) {
                avatar
                VStack(alignment: .leading, spacing: 0) {
                    Text(profileStore.activeProfile?.name ?? "Perfil")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(isFocused ? 1 : 0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isFocused {
                        Text("Alternar Perfil")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 12)
                if !isFocused {
                    SidebarClock()
                        .layoutPriority(1)
                        .transition(.opacity)
                }
            }
            .frame(height: 55)
        }
        .buttonStyle(SidebarHeaderButtonStyle())
        .focused($isFocused)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var avatar: some View {
        ProfileAvatarView(
            name: profileStore.activeProfile?.name ?? "",
            avatarAsset: profileStore.activeProfile?.avatarAsset,
            size: 55
        )
        .scaleEffect(isFocused ? 1.06 : 1)
    }
}

private struct SidebarHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct SidebarClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
        .padding(.trailing, 20)
    }
}
