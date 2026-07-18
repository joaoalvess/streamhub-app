import SwiftUI

struct AppRootGate: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PlaybackProgressStore.self) private var progressStore

    var body: some View {
        ZStack {
            if let profile = profileStore.activeProfile {
                RootView()
                    .id(profile.id)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                ProfileSelectionView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: profileStore.activeProfileID)
        .onChange(of: profileStore.activeProfileID, initial: true) { _, id in
            if let id, id == profileStore.profiles.first?.id {
                progressStore.adoptLegacyDataIfNeeded(for: id)
            }
            progressStore.setActiveProfile(id)
        }
    }
}
