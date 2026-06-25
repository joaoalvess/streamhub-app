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
        .preferredColorScheme(.dark)
        .background(Theme.bg)
    }

    @ViewBuilder
    private func destination(for section: MenuSection) -> some View {
        switch section {
        case .filmes:
            HomeView(tag: "movie", heroCatalogId: "mdblist.2236")
        case .series:
            HomeView(tag: "series", heroCatalogId: "tmdb.trending_series")
        case .animes:
            HomeView(tag: "anime", heroCatalogId: "mal.season_top_anime")
        default:
            ComingSoonView(title: section.title, icon: section.icon)
        }
    }
}

#Preview {
    RootView()
}
