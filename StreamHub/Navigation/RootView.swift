import SwiftUI

struct RootView: View {
    @Environment(ProfileStore.self) private var profileStore

    var body: some View {
        MenuTabView(storageKey: "menu.lastSection.\(profileStore.activeProfileID?.uuidString ?? "none")")
    }
}

private struct MenuTabView: View {
    @AppStorage private var lastSection: String
    @State private var selection: MenuSection

    init(storageKey: String) {
        _lastSection = AppStorage(wrappedValue: "", storageKey)
        _selection = State(initialValue: MenuSection.restored(from: UserDefaults.standard.string(forKey: storageKey)))
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(MenuSection.principais) { section in
                Tab(value: section) {
                    destination(for: section)
                } label: {
                    MenuLabel(section: section)
                }
            }

            TabSection("Canais") {
                ForEach(MenuSection.canais) { section in
                    Tab(value: section) {
                        destination(for: section)
                    } label: {
                        MenuLabel(section: section)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarProfileHeader() }
        .preferredColorScheme(.dark)
        .background(Theme.bg)
        .onChange(of: selection) { _, section in
            guard section.isRestorable else { return }
            lastSection = section.rawValue
        }
    }

    @ViewBuilder
    private func destination(for section: MenuSection) -> some View {
        if section == .biblioteca {
            LibraryView()
        } else if let config = section.homeConfiguration {
            HomeView(config: config)
        } else {
            SearchView()
        }
    }
}

#Preview {
    RootView()
        .environment(ProfileStore())
}
