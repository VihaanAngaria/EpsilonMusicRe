import SwiftUI

@main
struct EpsilonMusicReApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerManager.shared
    @StateObject private var account = AccountManager.shared
    @StateObject private var downloads = DownloadManager.shared
    @StateObject private var recognition = RecognitionManager.shared
    @StateObject private var lt = ListenTogetherClient.shared
    @StateObject private var discord = DiscordPresence.shared
    @StateObject private var scrobbler = Scrobbler.shared
    @StateObject private var spotify = SpotifyImporter.shared
    @StateObject private var updater = Updater.shared
    @StateObject private var eq = EqualizerEngine.shared
    @StateObject private var ai = AIClient.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(account)
                .environmentObject(downloads)
                .environmentObject(recognition)
                .environmentObject(lt)
                .environmentObject(discord)
                .environmentObject(scrobbler)
                .environmentObject(spotify)
                .environmentObject(updater)
                .environmentObject(eq)
                .environmentObject(ai)
        }
    }
}
