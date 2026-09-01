import SwiftUI

/// Full-screen player — mirrors the Android Player screen:
/// swipeable pager [Up next | Artwork | Related], title + like,
/// seek slider, transport controls (shuffle / prev / play / next / repeat),
/// lyrics toggle, and the more menu (sleep timer, radio, add to playlist, share).
struct PlayerView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var pageSelection = 1        // 0 = queue, 1 = artwork, 2 = related
    @State private var showLyrics = false
    @State private var showAddSheet = false
    @State private var relatedSongs: [Song] = []
    @State private var relatedLoaded = false
    @State private var showSleepMenu = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if showLyrics {
                LyricsView(isPresented: $showLyrics)
            } else {
                pager
                    .frame(maxHeight: .infinity)
            }
            controls
        }
        .background(
            ZStack {
                pal.background
                LinearGradient(colors: [pal.accent.opacity(0.14), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showAddSheet) {
            if let song = player.currentSong {
                AddToPlaylistSheet(song: song)
            }
        }
        .confirmationDialog("Sleep timer", isPresented: $showSleepMenu, titleVisibility: .visible) {
            Button("Off") { player.clearSleepTimer() }
            Button("15 minutes") { player.setSleepTimer(minutes: 15) }
            Button("30 minutes") { player.setSleepTimer(minutes: 30) }
            Button("60 minutes") { player.setSleepTimer(minutes: 60) }
            Button("End of track") { player.setSleepAtEndOfTrack() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 2) {
                    Text("Playing from")
                        .font(.system(size: 10))
                        .foregroundStyle(pal.textSecondary)
                    Text(player.queueSourceName.isEmpty ? "Epsilon Music" : player.queueSourceName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 180)
                Spacer()
                Menu {
                    if let song = player.currentSong {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add to playlist", systemImage: "music.note.list")
                        }
                        Button {
                            player.startRadio(for: song)
                        } label: {
                            Label("Start radio", systemImage: "dot.radiowaves.left.and.right")
                        }
                        if let url = URL(string: "https://music.youtube.com/watch?v=\(song.videoId)") {
                            Link(destination: url) {
                                Label("Open in YouTube Music", systemImage: "safari")
                            }
                        }
                        ShareLink(item: "https://music.youtube.com/watch?v=\(song.videoId)") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showSleepMenu = true
                    } label: {
                        Label("Sleep timer", systemImage: "moon.zzz")
                    }
                    Button(role: .destructive) {
                        player.stop()
                        dismiss()
                    } label: {
                        Label("Stop playback", systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: Pager

    private var pager: some View {
        TabView(selection: $pageSelection) {
            queuePage.tag(0)
            artworkPage.tag(1)
            relatedPage.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: pageSelection) { newPage in
            if newPage == 2, !relatedLoaded, let song = player.currentSong, !song.isLocal {
                loadRelated(for: song)
            }
        }
    }

    // MARK: Artwork page

    private var artworkPage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            SongThumb(url: player.currentSong?.thumbnailUrl, size: artworkSize, corner: 20)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            if let song = player.currentSong {
                VStack(spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(pal.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(song.artistsText.isEmpty ? "Unknown artist" : song.artistsText)
                        .font(.system(size: 14))
                        .foregroundStyle(pal.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)
                HStack(spacing: 20) {
                    Button {
                        library.toggleLike(song)
                    } label: {
                        Image(systemName: library.isLiked(song) ? "heart.fill" : "heart")
                            .font(.system(size: 20))
                            .foregroundStyle(library.isLiked(song) ? pal.accent : pal.textSecondary)
                    }
                    .buttonStyle(.plain)
                    if let album = song.album, !album.isEmpty {
                        Text("From \(album)")
                            .font(.system(size: 11))
                            .foregroundStyle(pal.textSecondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
    }

    private var artworkSize: CGFloat {
        UIScreen.main.bounds.width - 96
    }

    // MARK: Queue page

    private var queuePage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Up next")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                Spacer()
                if !player.upNextSongs.isEmpty {
                    Button {
                        player.clearQueue(keepingCurrent: true)
                    } label: {
                        Text("Clear")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(pal.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                        queueRow(song, index: index)
                    }
                }
            }
        }
    }

    private func queueRow(_ song: Song, index: Int) -> some View {
        let isCurrent = player.currentSong?.id == song.id
        return HStack(spacing: 12) {
            SongThumb(url: song.thumbnailUrl, size: 44, corner: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? pal.accent : pal.textPrimary)
                    .lineLimit(1)
                Text(song.artistsText.isEmpty ? "—" : song.artistsText)
                    .font(.system(size: 11))
                    .foregroundStyle(pal.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 13))
                    .foregroundStyle(pal.accent)
            } else {
                Menu {
                    Button {
                        player.removeFromQueue(at: index)
                    } label: {
                        Label("Remove from queue", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pal.textSecondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            player.playAt(index: index)
        }
    }

    // MARK: Related page

    private var relatedPage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Related")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if !relatedLoaded {
                        HStack { Spacer(); ProgressView().padding(.vertical, 30); Spacer() }
                    } else if relatedSongs.isEmpty {
                        EmptyPlaceholder(icon: "sparkles", text: "No related songs for this track.")
                    } else {
                        ForEach(Array(relatedSongs.enumerated()), id: \.element.id) { _, song in
                            HStack(spacing: 12) {
                                SongThumb(url: song.thumbnailUrl, size: 44, corner: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(pal.textPrimary)
                                        .lineLimit(2)
                                    Text(song.artistsText.isEmpty ? "—" : song.artistsText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(pal.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(song, queue: relatedSongs, sourceName: "Related")
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadRelated(for song: Song) {
        Task { @MainActor in
            do {
                let radio = try await InnerTube.shared.radio(videoId: song.videoId)
                relatedSongs = radio.filter { $0.videoId != song.videoId }
            } catch {
                relatedSongs = []
            }
            relatedLoaded = true
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            // Seek slider + times.
            VStack(spacing: 2) {
                PlayerSlider(position: player.position, duration: max(player.duration, 0)) { newValue in
                    player.seek(to: newValue)
                }
                HStack {
                    Text(formatDuration(Int(max(0, player.position))))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(pal.textSecondary)
                    Spacer()
                    if let song = player.currentSong, let d = song.duration, d > 0, player.duration <= 0 {
                        Text(formatDuration(d))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(pal.textSecondary)
                    } else {
                        Text(formatDuration(Int(max(0, player.duration))))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(pal.textSecondary)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, 8)

            // Transport row.
            HStack(spacing: 0) {
                controlButton(icon: "shuffle", active: player.shuffle, size: 22) {
                    player.toggleShuffle()
                }
                .frame(maxWidth: .infinity)
                controlButton(icon: "backward.fill", active: false, size: 30) {
                    player.previous()
                }
                .frame(maxWidth: .infinity)
                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(pal.accent)
                            .frame(width: 68, height: 68)
                        if player.isBuffering {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.1)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                controlButton(icon: "forward.fill", active: false, size: 30) {
                    player.next()
                }
                .frame(maxWidth: .infinity)
                controlButton(icon: repeatIcon, active: player.repeatMode != .off, size: 20) {
                    player.cycleRepeat()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)

            // Secondary row: lyrics toggle, error message, sleep indicator.
            HStack(spacing: 0) {
                Button {
                    showLyrics.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.quote")
                        Text("Lyrics")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showLyrics ? pal.accent : pal.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
                if player.sleepRemaining > 0 {
                    Text("Sleep \(formatDuration(player.sleepRemaining))")
                        .font(.system(size: 11))
                        .foregroundStyle(pal.textSecondary)
                } else if player.sleepRemaining == -1 {
                    Text("Sleep: end of track")
                        .font(.system(size: 11))
                        .foregroundStyle(pal.textSecondary)
                }
                if let error = player.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(pal.accent.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(pageSelection == 0 ? pal.accent : pal.textSecondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(pageSelection == 1 ? pal.accent : pal.textSecondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(pageSelection == 2 ? pal.accent : pal.textSecondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
        .padding(.top, 6)
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func controlButton(icon: String, active: Bool, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? pal.accent : pal.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slider (Android BigSeekBar style)

struct PlayerSlider: View {
    let position: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @Environment(\.epsPalette) private var pal
    @State private var dragging = false
    @State private var dragValue: Double = 0

    private var effectivePosition: Double {
        dragging ? dragValue : position
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, effectivePosition / duration))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(pal.surfaceHighest)
                    .frame(height: 4)
                Capsule()
                    .fill(pal.accent)
                    .frame(width: max(4, width * progress), height: 4)
                Circle()
                    .fill(pal.textPrimary)
                    .frame(width: dragging ? 18 : 12, height: dragging ? 18 : 12)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .offset(x: max(0, min(width - 12, width * progress - 6)))
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        dragValue = max(0, min(duration, Double(value.location.x / max(width, 1)) * duration))
                    }
                    .onEnded { value in
                        let target = max(0, min(duration, Double(value.location.x / max(width, 1)) * duration))
                        dragging = false
                        onSeek(target)
                    }
            )
        }
        .frame(height: 28)
        .padding(.horizontal, 16)
    }
}
