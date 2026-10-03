import SwiftUI

struct AppRootGate: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PlaybackProgressStore.self) private var progressStore
    @Environment(RecentSearchesStore.self) private var recentSearches
    @Environment(PlaybackCoordinator.self) private var coordinator
    @State private var router = DetailRouter()

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
        .fullScreenCover(item: routerTarget) { target in
            MediaWindowView(row: target.row, startIndex: target.index, autoplay: target.autoplay)
        }
        .environment(router)
        .onChange(of: profileStore.activeProfileID, initial: true) { _, id in
            applyProfile(id)
        }
        .task(id: topShelfSnapshot) {
            guard let snapshot = topShelfSnapshot else { return }
            TopShelfPublisher.publish(snapshot)
            await TopShelfArtwork.prepare(snapshot)
        }
        .onOpenURL(perform: handleIncomingURL)
    }

    private var routerTarget: Binding<DetailRouter.Target?> {
        Binding(get: { router.target }, set: { router.target = $0 })
    }

    private var topShelfSnapshot: TopShelfSnapshot? {
        TopShelfPublisher.snapshot(profileID: progressStore.activeProfileID, entries: progressStore.entries)
    }

    private func applyProfile(_ id: UUID?) {
        if let id, id == profileStore.profiles.first?.id {
            progressStore.adoptLegacyDataIfNeeded(for: id)
        }
        progressStore.setActiveProfile(id)
        recentSearches.setActiveProfile(id)
        if id == nil {
            router.close()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let link = TopShelfLink(url: url) else {
            coordinator.handleIncomingURL(url)
            return
        }
        open(link)
    }

    private func open(_ link: TopShelfLink) {
        guard let profile = profileStore.profiles.first(where: { $0.id == link.profileID }) else { return }
        if coordinator.nativeSession != nil {
            coordinator.completeNativeSession()
        }
        coordinator.dismissError()
        profileStore.select(profile)
        applyProfile(profile.id)
        let entries = progressStore.entries
        guard let index = entries.firstIndex(where: { $0.contentId == link.contentID }) else { return }
        router.open(row: .continueWatching(entries: entries), index: index, autoplay: link.action == .play)
    }
}
