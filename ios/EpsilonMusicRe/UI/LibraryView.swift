import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @State private var segment = 0
    @State private var searchText = ""

    private var filteredSongs: [Song] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.songs }
        return library.songs.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    private var filteredArtists: [ArtistGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.artists }
        return library.artists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Library section", selection: $segment) {
                    Text("Songs").tag(0)
                    Text("Artists").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if segment == 0 {
                    songsList
                } else {
                    artistsList
                }
            }
            .background(Color.epsBackground)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: Text("Search"))
        }
    }

    private var songsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredSongs.isEmpty {
                    Text("No songs found.")
                        .font(.system(size: 14))
                        .foregroundColor(.epsTextSecondary)
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(filteredSongs) { song in
                        SongRow(song: song, songs: filteredSongs)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var artistsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredArtists.isEmpty {
                    Text("No artists found.")
                        .font(.system(size: 14))
                        .foregroundColor(.epsTextSecondary)
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(filteredArtists) { group in
                        NavigationLink {
                            SongListView(title: group.name, songs: group.songs)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.epsSurfaceHighlighted)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.epsAccent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.epsTextPrimary)
                                    Text("\(group.songs.count) song\(group.songs.count == 1 ? "" : "s")")
                                        .font(.system(size: 12))
                                        .foregroundColor(.epsTextSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.epsTextSecondary.opacity(0.6))
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

struct SongListView: View {
    let title: String
    let songs: [Song]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(songs) { song in
                    SongRow(song: song, songs: songs)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.epsBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
