import SwiftUI

@main
struct EpsilonMusicReApp: App {
    @StateObject private var library = MusicLibraryStore()
    @StateObject private var player = PlayerManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(.epsAccent)
        }
    }
}
