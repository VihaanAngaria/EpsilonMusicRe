import SwiftUI

// MARK: - Navigation title bar (Android NavigationTitle equivalent)

struct NavigationTitleBar<Trailing: View>: View {
    let title: String
    var showLogo: Bool = false
    var showBack: Bool = false
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            if showBack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showLogo {
                Image("logo")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(pal.accent)
            }
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundStyle(pal.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Chips row (Android ChipsRow)

struct ChipsRow<T: Hashable & Identifiable>: View {
    let options: [(T, String)]
    let isSelected: (T) -> Bool
    let onSelect: (T) -> Void

    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    let selected = isSelected(option.0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            onSelect(option.0)
                        }
                    } label: {
                        Text(option.1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selected ? pal.textPrimary : pal.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selected ? pal.surfaceHighest : pal.surface)
                            )
                            .overlay(
                                Capsule().strokeBorder(selected ? pal.accent.opacity(0.9) : pal.surfaceHighest.opacity(0.7), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Thumbnail

struct SongThumb: View {
    let url: String?
    var size: CGFloat = 48
    var corner: CGFloat = 8
    var circle: Bool = false

    @Environment(\.epsPalette) private var pal

    var body: some View {
        Group {
            if let urlString = url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        Rectangle().fill(pal.surfaceHighest)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(circle ? Circle() : RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(pal.surfaceHighest)
            Image(systemName: circle ? "person.crop.circle" : "music.note")
                .font(.system(size: size * 0.38))
                .foregroundStyle(pal.textSecondary.opacity(0.7))
        }
    }
}

// MARK: - Song row (Android Items SongItem equivalent)

struct SongRow: View {
    let song: Song
    var showIndex: Int? = nil
    var showLike: Bool = true
    var isCurrent: Bool = false
    var subtitleOverride: String? = nil
    var onPlay: (Song, [Song]) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal
    @State private var showAddSheet = false

    var body: some View {
        HStack(spacing: 12) {
            if let index = showIndex {
                Text("\(index)")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.textSecondary)
                    .frame(width: 28)
            }
            SongThumb(url: song.thumbnailUrl, size: 48, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? pal.accent : pal.textPrimary)
                    .lineLimit(2)
                Text(subtitleOverride ?? song.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showLike {
                Button {
                    library.toggleLike(song)
                } label: {
                    Image(systemName: library.isLiked(song) ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(library.isLiked(song) ? pal.accent : pal.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Menu {
                songMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(pal.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay(song, [])
        }
        .sheet(isPresented: $showAddSheet) {
            AddToPlaylistSheet(song: song)
        }
    }

    @ViewBuilder
    private var songMenu: some View {
        Button {
            player.playNext(song)
        } label: {
            Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button {
            player.addToQueue(song)
        } label: {
            Label("Add to queue", systemImage: "text.badge.plus")
        }
        Button {
            player.startRadio(for: song)
        } label: {
            Label("Start radio", systemImage: "dot.radiowaves.left.and.right")
        }
        if !song.isLocal {
            Button {
                showAddSheet = true
            } label: {
                Label("Add to playlist", systemImage: "music.note.list")
            }
            if let url = URL(string: "https://music.youtube.com/watch?v=\(song.videoId)") {
                Link(destination: url) {
                    Label("Open in YouTube Music", systemImage: "safari")
                }
            }
        }
    }
}

// MARK: - Artist row

struct ArtistRow: View {
    let artist: ArtistItem
    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 12) {
            SongThumb(url: artist.thumbnail, size: 56, corner: 28, circle: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(pal.textPrimary)
                    .lineLimit(1)
                Text("Artist")
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pal.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Media card (Android Items grid cards)

struct MediaCard: View {
    let title: String
    let subtitle: String?
    let thumbnail: String?
    var isCircle: Bool = false
    var width: CGFloat = 150

    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SongThumb(url: thumbnail, size: width, corner: isCircle ? width / 2 : 10, circle: isCircle)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(pal.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(pal.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
    }
}

// MARK: - Horizontal shelf (Android carousels)

struct ItemShelf: View {
    let shelf: Shelf
    var circleItems: Bool = false
    var onPlaySong: (Song, [Song]) -> Void

    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelf.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(pal.textPrimary)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.items) { item in
                        shelfCard(item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func shelfCard(_ item: GridItem) -> some View {
        let songsInShelf = shelf.items.compactMap { if case .song(let s) = $0 { return s } else { return nil } }
        switch item {
        case .song(let song):
            // Songs play immediately — no navigation.
            MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
                .contentShape(Rectangle())
                .onTapGesture {
                    onPlaySong(song, songsInShelf.isEmpty ? [song] : songsInShelf)
                }
        case .artist(let artist):
            NavigationLink(value: Route.artist(artist)) {
                MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail, isCircle: circleItems)
            }
            .buttonStyle(.plain)
        case .album(let album):
            NavigationLink(value: Route.album(album)) {
                MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
            }
            .buttonStyle(.plain)
        case .playlist(let playlist):
            NavigationLink(value: Route.onlinePlaylist(playlist)) {
                MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Empty placeholder (Android EmptyPlaceholder)

struct EmptyPlaceholder: View {
    let icon: String
    let text: String
    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(pal.textSecondary.opacity(0.6))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(pal.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
    }
}

// MARK: - Error / loading helpers

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)?

    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
                .multilineTextAlignment(.center)
            if let retry = onRetry {
                Button("Retry") { retry() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pal.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(pal.surface))
        .padding(.horizontal, 16)
    }
}

// MARK: - Play & shuffle header buttons (Android library headers)

struct PlayShuffleButtons: View {
    let onPlay: () -> Void
    let onShuffle: () -> Void

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onShuffle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                    Text("Shuffle")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(pal.surface))
                .overlay(Capsule().strokeBorder(pal.surfaceHighest, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button {
                onPlay()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(pal.accent))
            }
            .buttonStyle(.plain)
        }
    }
}

extension EpsPalette {
    /// Text color used on filled accent buttons.
    var onPlayText: Color {
        .white
    }
}

// MARK: - Add to playlist sheet

struct AddToPlaylistSheet: View {
    let song: Song
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal
    @State private var newPlaylistName = ""
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                if !library.playlists.isEmpty {
                    Section("Your playlists") {
                        ForEach(library.playlists) { playlist in
                            Button {
                                _ = library.addToPlaylist(playlist.id, song: song)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    SongThumb(url: playlist.thumbnailUrl, size: 44, corner: 6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .foregroundStyle(pal.textPrimary)
                                        Text("\(playlist.songCount) songs")
                                            .font(.system(size: 12))
                                            .foregroundStyle(pal.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(pal.accent)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("New playlist", systemImage: "plus")
                            .foregroundStyle(pal.accent)
                    }
                }
            }
            .navigationTitle("Add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("New playlist", isPresented: $showCreate) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        _ = library.createPlaylist(named: name, songs: [song])
                    }
                    newPlaylistName = ""
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    newPlaylistName = ""
                }
            } message: {
                Text("\"\(song.title)\" will be added to the new playlist.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var trailingText: String? = nil
    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Spacer()
            if let trailing = trailingText {
                Text(trailing)
                    .font(.system(size: 13))
                    .foregroundStyle(pal.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
