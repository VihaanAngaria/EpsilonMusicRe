import SwiftUI
import AVKit

/// Full-screen player — mirrors the Android Player screen:
/// swipeable pager [Up next | Artwork | Related], title + like,
/// seek slider (plain or wavy), transport controls (shuffle / prev / play /
/// next / repeat), volume row, lyrics toggle, comments, queue sheet, download,
/// canvas animated artwork / rotating vinyl, background styles, sleep timer,
/// radio, media details and share.
struct PlayerView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var eq: EqualizerEngine
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var pageSelection = 1        // 0 = queue, 1 = artwork, 2 = related
    @State private var showLyrics = false
    @State private var showAddSheet = false
    @State private var relatedSongs: [Song] = []
    @State private var relatedLoaded = false
    @State private var showSleepMenu = false
    @State private var showComments = false
    @State private var showQueueSheet = false
    @State private var showMediaInfo = false
    @State private var mediaInfo: MediaInfoResult?
    @State private var artworkImage: UIImage?
    @State private var canvasUrl: String?
    @State private var canvasChecked = false

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
            volumeRow
        }
        .background(playerBackground)
        .sheet(isPresented: $showAddSheet) {
            if let song = player.currentSong {
                AddToPlaylistSheet(song: song)
            }
        }
        .sheet(isPresented: $showComments) {
            if let song = player.currentSong {
                CommentsSheet(videoId: song.videoId)
            }
        }
        .sheet(isPresented: $showQueueSheet) {
            QueueSheet()
        }
        .sheet(isPresented: $showMediaInfo) {
            MediaInfoSheet(info: $mediaInfo)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Sleep timer", isPresented: $showSleepMenu, titleVisibility: .visible) {
            Button("Off") { player.clearSleepTimer() }
            Button("5 minutes") { player.setSleepTimer(minutes: 5) }
            Button("15 minutes") { player.setSleepTimer(minutes: 15) }
            Button("30 minutes") { player.setSleepTimer(minutes: 30) }
            Button("60 minutes") { player.setSleepTimer(minutes: 60) }
            Button("End of track") { player.setSleepAtEndOfTrack() }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: player.currentSong?.id) {
            artworkImage = nil
            canvasUrl = nil
            canvasChecked = false
            await loadArtwork()
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
                        if !song.isLocal {
                            Button {
                                showComments = true
                            } label: {
                                Label("Comments", systemImage: "bubble.left.and.bubble.right")
                            }
                            Button {
                                showMediaInfo = true
                                loadMediaInfo()
                            } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                            Button {
                                Task {
                                    if let result = try? await InnerTube.shared.search(query: "\(song.artistsText) \(song.album ?? song.title)", filter: .albums),
                                       case .album(let album) = result.items.first(where: { item in
                                           if case .album = item { return true }
                                           return false
                                       }) {
                                        library.recordVisitedAlbum(album)
                                    }
                                }
                            } label: {
                                Label("Open album", systemImage: "square.stack")
                            }
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
            artwork
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
                    if !song.isLocal {
                        DownloadButton(song: song)
                    }
                    Button {
                        showComments = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 18))
                            .foregroundStyle(pal.textSecondary)
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

    /// Artwork with canvas video, rotating vinyl and double-tap seek gestures
    /// (Thumbnail.kt parity).
    @ViewBuilder
    private var artwork: some View {
        let base = Group {
            if let url = canvasUrl, settings.canvasThumbnail, !settings.rotatingThumbnail {
                CanvasVideoPlayer(urlString: url, isPlaying: player.isPlaying, staticUrl: player.currentSong?.thumbnailUrl)
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if settings.rotatingThumbnail {
                RotatingArtworkView(urlString: player.currentSong?.thumbnailUrl, isPlaying: player.isPlaying)
                    .frame(width: artworkSize, height: artworkSize)
            } else {
                SongThumb(url: player.currentSong?.thumbnailUrl, size: artworkSize, corner: 20)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            }
        }
        base
            .contentShape(Rectangle())
            .gesture(doubleTapSeekGesture)
    }

    /// Double-tap left/right thirds seek ±5 s, middle toggles play (Thumbnail.kt).
    private var doubleTapSeekGesture: some Gesture {
        SpatialTapGesture(count: 2).onEnded { value in
            let third = artworkSize / 3
            let x = value.location.x
            if x < third {
                player.seek(to: max(0, player.position - 5))
            } else if x > third * 2 {
                player.seek(to: min(max(player.duration, 5), player.position + 5))
            } else {
                player.togglePlayPause()
            }
        }
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
                if settings.wavySlider {
                    WavySlider(position: player.position, duration: max(player.duration, 0)) { newValue in
                        player.seek(to: newValue)
                    }
                } else {
                    PlayerSlider(position: player.position, duration: max(player.duration, 0)) { newValue in
                        player.seek(to: newValue)
                    }
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

            // Secondary row: queue sheet, lyrics toggle, error message, sleep indicator.
            HStack(spacing: 0) {
                Button {
                    showQueueSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text("Queue")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pal.textSecondary)
                }
                .buttonStyle(.plain)
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
                .padding(.leading, 20)
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

    // MARK: Volume row (Player.kt volume slider parity)

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundStyle(pal.textSecondary)
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.volume = Float($0) }), in: 0...1)
                .tint(pal.accent)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundStyle(pal.textSecondary)
            if settings.showCodecOnPlayer, let codec = player.currentCodec {
                Text(codecChip(codec))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(pal.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(pal.surface))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private func codecChip(_ codec: String) -> String {
        var parts: [String] = []
        let short = codec.hasPrefix("mp4.40") ? "AAC" : codec
        parts.append(short.uppercased())
        if let bitrate = player.currentBitrate {
            parts.append("\(bitrate / 1000)kb/s")
        }
        if let rate = player.currentSampleRate {
            parts.append("\(rate / 1000)kHz")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Background (PlayerBackgroundStyle parity)

    @ViewBuilder
    private var playerBackground: some View {
        ZStack {
            pal.background
            switch settings.playerBackgroundStyle {
            case .default:
                EmptyView()
            case .gradient:
                LinearGradient(colors: [pal.accent.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .center)
            case .blur:
                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 60)
                        .opacity(0.55)
                } else {
                    LinearGradient(colors: [pal.accent.opacity(0.16), .clear],
                                   startPoint: .top, endPoint: .center)
                }
            case .glowAnimated, .ambient:
                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 80)
                        .opacity(0.4)
                        .overlay(pal.accent.opacity(0.08))
                } else {
                    LinearGradient(colors: [pal.accent.opacity(0.2), pal.accent.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Data helpers

    private func loadArtwork() async {
        guard let song = player.currentSong else { return }
        if let urlString = song.thumbnailUrl, let url = URL(string: urlString) {
            if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                artworkImage = image
            }
        }
        // Canvas lookup (Apple Music motion → epsilonmusic manifest).
        if settings.canvasThumbnail, !canvasChecked, !song.isLocal {
            canvasChecked = true
            if let canvas = await CanvasProvider.lookupCanvas(song: song) {
                canvasUrl = canvas.videoUrl ?? canvas.animatedUrl
            }
        }
    }

    private func loadMediaInfo() {
        guard let song = player.currentSong, mediaInfo == nil else { return }
        Task { @MainActor in
            mediaInfo = await InnerTube.shared.mediaInfo(videoId: song.videoId)
        }
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

// MARK: - Wavy slider (SquigglySlider parity)

struct WavySlider: View {
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
                WavyWave(amplitude: 3, phase: 0)
                    .stroke(pal.surfaceHighest, lineWidth: 3)
                WavyWave(amplitude: 3.5, phase: 0.6)
                    .stroke(pal.accent, lineWidth: 3)
                    .frame(width: max(6, width * progress))
                    .clipped()
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

    struct WavyWave: Shape {
        let amplitude: CGFloat
        let phase: Double

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let steps = max(24, Int(rect.width / 6))
            for step in 0...steps {
                let x = CGFloat(step) / CGFloat(steps) * rect.width
                let wavePhase = Double(x / 22) + phase
                let y = rect.midY + CGFloat(sin(wavePhase)) * amplitude
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            return path
        }
    }
}

// MARK: - Rotating artwork (clover vinyl — Thumbnail.kt rotatingThumbnail)

struct RotatingArtworkView: View {
    let urlString: String?
    let isPlaying: Bool

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color(white: 0.15)
                }
            }
            .frame(width: 300, height: 300)
            .clipShape(CloverShape(sides: 8, outerRadius: 150, innerRadius: 0.92))
        }
        .frame(width: 300, height: 300)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .rotationEffect(.degrees(isPlaying ? rotation : 0))
    }
}

/// 8-leaf clover cookie (MaterialShapes.Clover8Leaf parity).
struct CloverShape: Shape {
    let sides: Int
    let outerRadius: CGFloat
    var innerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let points = 48
        for i in 0...points {
            let angle = Double(i) / Double(points) * 2 * .pi
            // Ruffled edge: base circle with petal modulation.
            let petal = abs(cos(Double(sides) * angle / 2))
            let radius = outerRadius * (innerRadius + (1 - innerRadius) * pow(petal, 2))
            let x = center.x + radius * CGFloat(cos(angle))
            let y = center.y + radius * CGFloat(sin(angle))
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Canvas video player (CanvasArtworkPlayer parity — muted looping video)

struct CanvasVideoPlayer: UIViewRepresentable {
    let urlString: String
    let isPlaying: Bool
    let staticUrl: String?

    func makeUIView(context: Context) -> UIView {
        let view = VideoContainerView()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let container = uiView as? VideoContainerView else { return }
        container.configure(urlString: urlString, isPlaying: isPlaying, staticUrl: staticUrl)
    }

    final class VideoContainerView: UIView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        private var configuredUrl: String?

        init() {
            super.init(frame: .zero)
            backgroundColor = .black
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspectFill
            playerLayer = layer
            self.layer.addSublayer(layer)
            NotificationCenter.default.addObserver(self, selector: #selector(itemEnded), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        @objc private func itemEnded() {
            player?.seek(to: .zero)
            player?.play()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }

        func configure(urlString: String, isPlaying: Bool, staticUrl: String?) {
            if configuredUrl != urlString, let url = URL(string: urlString) {
                configuredUrl = urlString
                let item = AVPlayerItem(url: url)
                let player = AVPlayer(playerItem: item)
                player.isMuted = true
                self.player = player
                playerLayer?.player = player
            }
            if isPlaying {
                player?.play()
            } else {
                player?.pause()
            }
        }
    }
}

// MARK: - Media info sheet (ShowMediaInfo + RYD dislikes parity)

struct MediaInfoSheet: View {
    @Binding var info: MediaInfoResult?
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let info = info {
                    VStack(alignment: .leading, spacing: 14) {
                        infoRow("Title", info.title)
                        infoRow("Channel", info.channelName)
                        if let date = info.publishDate { infoRow("Published", date) }
                        if let views = info.viewCount { infoRow("Views", views) }
                        if let likes = info.likeCount { infoRow("Likes", likes) }
                        if let dislikes = info.dislikeCount { infoRow("Dislikes (est.)", "\(dislikes)") }
                        if let subs = info.subscriberCount { infoRow("Subscribers", subs) }
                        if let codec = player.currentCodec {
                            infoRow("Stream", Self.streamDescription(codec, bitrate: player.currentBitrate, sampleRate: player.currentSampleRate))
                        }
                    }
                    .padding(16)
                } else {
                    HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
                }
                Color.clear.frame(height: 40)
            }
            .background(pal.background.ignoresSafeArea())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
                .frame(width: 110, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(pal.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    static func streamDescription(_ codec: String, bitrate: Int?, sampleRate: Int?) -> String {
        var parts: [String] = ["AAC"]
        if let b = bitrate { parts.append("\(b / 1000) kb/s") }
        if let r = sampleRate { parts.append("\(r / 1000) kHz") }
        return parts.joined(separator: " · ")
    }
}
