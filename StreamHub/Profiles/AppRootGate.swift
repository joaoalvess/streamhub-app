import SwiftUI

struct AppRootGate: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PlaybackProgressStore.self) private var progressStore
    @Environment(RecentSearchesStore.self) private var recentSearches
    @Environment(MyListStore.self) private var myList
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
        .toastHost()
        .fullScreenCover(item: routerTarget) { target in
            MediaWindowView(row: target.row, startIndex: target.index, autoplay: target.autoplay)
                .toastHost()
        }
        .environment(router)
        .onChange(of: profileStore.activeProfileID, initial: true) { _, id in
            applyProfile(id)
        }
        .onChange(of: profileStore.profiles, initial: true) { _, profiles in
            clearTopShelfIfOrphaned(profiles: profiles)
        }
        .task(id: topShelfSnapshot) {
            guard let snapshot = topShelfSnapshot else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
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
            recentSearches.adoptLegacyDataIfNeeded(for: id)
            myList.adoptLegacyDataIfNeeded(for: id)
        }
        progressStore.setActiveProfile(id)
        recentSearches.setActiveProfile(id)
        myList.setActiveProfile(id)
        if id == nil {
            router.close()
        }
    }

    private func clearTopShelfIfOrphaned(profiles: [Profile]) {
        guard let defaults = TopShelfStorage.sharedDefaults(),
              let snapshot = TopShelfStorage.load(from: defaults),
              !profiles.contains(where: { $0.id == snapshot.profileID }) else { return }
        TopShelfPublisher.clear(from: defaults)
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
        let row = CatalogRow.continueWatching(entries: entries)
        let autoplay = link.action == .play
        guard router.target != nil else {
            router.open(row: row, index: index, autoplay: autoplay)
            return
        }
        router.close()
        Task { [router] in
            await Task.yield()
            router.open(row: row, index: index, autoplay: autoplay)
        }
    }
}
