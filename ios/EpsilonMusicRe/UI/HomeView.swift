import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: MusicLibraryStore

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5: return "Good night"
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var homeSongs: [Song] {
        Array(library.songs.prefix(10))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    quickTiles
                    if library.isLoading {
                        ProgressView("Loading library…")
                            .tint(.epsAccent)
                            .foregroundColor(.epsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                    if library.songs.isEmpty && !library.isLoading {
                        Text("No songs available yet.")
                            .font(.system(size: 14))
                            .foregroundColor(.epsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                    if !homeSongs.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: library.isUsingDemoTracks ? "Demo Tracks" : "Your Library")
                            ForEach(homeSongs) { song in
                                SongRow(song: song, songs: homeSongs)
                            }
                        }
                    }
                    if library.libraryAccessDenied {
                        Text("Music library access was denied, so Epsilon Music is showing bundled demo tracks. Enable access in Settings to browse your songs.")
                            .font(.system(size: 12))
                            .foregroundColor(.epsTextSecondary)
                            .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.epsBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            LogoMark(size: 40, tint: .epsAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Epsilon Music")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.epsTextPrimary)
                Text(greeting)
                    .font(.system(size: 13))
                    .foregroundColor(.epsTextSecondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var quickTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            QuickTile(
                title: "Shuffle All",
                icon: "shuffle",
                isFeatured: true
            ) {
                let songs = library.songs
                if !songs.isEmpty {
                    player.playQueue(songs.shuffled(), startAt: 0)
                }
            }
            QuickTile(
                title: "Play All",
                icon: "play.fill"
            ) {
                let songs = library.songs
                if !songs.isEmpty {
                    player.playQueue(songs, startAt: 0)
                }
            }
        }
    }
}

struct QuickTile: View {
    let title: String
    let icon: String
    var isFeatured: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isFeatured ? Color.epsAccent : Color.epsSurfaceHighlighted)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isFeatured ? .white : .epsAccent)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.epsTextPrimary)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFeatured ? Color.epsSurfaceHighlighted : Color.epsSurface)
            )
        }
        .buttonStyle(.plain)
    }
}
