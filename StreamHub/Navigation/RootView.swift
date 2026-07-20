import SwiftUI

struct RootView: View {
    @State private var selection: MenuSection = .filmes

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
    }

    @ViewBuilder
    private func destination(for section: MenuSection) -> some View {
        if section == .search {
            SearchView()
        } else if let config = section.homeConfiguration {
            HomeView(config: config)
        }
    }
}

#Preview {
    RootView()
        .environment(ProfileStore())
}
