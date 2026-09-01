import SwiftUI

struct RootView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: MusicLibraryStore
    @State private var showPlayer = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            LibraryView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(1)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(player)
                .environmentObject(library)
        }
    }

    @ViewBuilder
    private var miniPlayer: some View {
        if player.currentSong != nil {
            MiniPlayerBar(onTap: { showPlayer = true })
        }
    }
}
