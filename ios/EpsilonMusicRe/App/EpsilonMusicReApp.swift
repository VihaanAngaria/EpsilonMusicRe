import SwiftUI

@main
struct EpsilonMusicReApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}
