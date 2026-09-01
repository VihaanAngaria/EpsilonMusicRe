import SwiftUI
import AVFoundation

// MARK: - Recognition screen (RecognitionScreen.kt parity)

struct RecognitionView: View {
    @EnvironmentObject private var recognition: RecognitionManager
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    @State private var micDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Music recognition", showBack: true) {
                    if !recognition.history.isEmpty {
                        NavigationLink {
                            RecognitionHistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(pal.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                micCard

                switch recognition.status {
                case .success(let result):
                    resultCard(result)
                case .noMatch(let message):
                    VStack(spacing: 10) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(pal.textSecondary)
                        Text(message)
                            .font(.system(size: 14))
                            .foregroundStyle(pal.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                case .error(let message):
                    ErrorBanner(message: message, onRetry: {
                        recognition.reset()
                    })
                    .padding(16)
                default:
                    EmptyView()
                }

                if !recognition.history.isEmpty {
                    SectionHeader(title: "Recent recognitions")
                    ForEach(Array(recognition.history.prefix(10))) { result in
                        compactResultRow(result)
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }

    private var micCard: some View {
        VStack(spacing: 14) {
            if case .listening(let elapsed) = recognition.status {
                // Pulsing mic.
                ZStack {
                    Circle()
                        .fill(pal.accent.opacity(0.2))
                        .frame(width: 130, height: 130)
                        .scaleEffect(1 + CGFloat(sin(elapsed * 3)) * 0.06)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(pal.accent)
                }
                Text("Listening… \(Int(elapsed))s / 10s")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(pal.textSecondary)
            } else if case .processing = recognition.status {
                ProgressView()
                    .scaleEffect(1.3)
                Text("Matching fingerprint…")
                    .font(.system(size: 14))
                    .foregroundStyle(pal.textSecondary)
            } else {
                Image(systemName: "waveform.and.person.filled")
                    .font(.system(size: 40))
                    .foregroundStyle(pal.accent)
                Text("Hold your phone up to the music — 10 seconds of audio is enough.")
                    .font(.system(size: 13))
                    .foregroundStyle(pal.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    startRecognition()
                } label: {
                    Label("Recognize", systemImage: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(pal.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func startRecognition() {
        guard micPermissionGranted() else {
            requestMicPermission()
            return
        }
        Task { await recognition.recognize() }
    }

    private func micPermissionGranted() -> Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    private func requestMicPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            Task { @MainActor in
                if granted {
                    await recognition.recognize()
                } else {
                    micDenied = true
                }
            }
        }
    }

    @ViewBuilder
    private func resultCard(_ result: RecognitionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SongThumb(url: result.coverArtHqUrl ?? result.coverArtUrl, size: 96, corner: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(pal.textPrimary)
                        .lineLimit(2)
                    Text(result.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(pal.textSecondary)
                        .lineLimit(1)
                    if let album = result.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 12))
                            .foregroundStyle(pal.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                if let genre = result.genre {
                    Label(genre, systemImage: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                }
                if let release = result.releaseDate {
                    Label(release, systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                }
                if let isrc = result.isrc {
                    Label("ISRC \(isrc)", systemImage: "barcode")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    playOnYouTubeMusic(result)
                } label: {
                    Label("Play on YouTube Music", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(pal.accent))
                }
                .buttonStyle(.plain)
                if let url = result.appleMusicUrl, let link = URL(string: url) {
                    Link(destination: link) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(pal.textPrimary)
                            .frame(width: 44, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                    }
                }
                if let url = result.spotifyUrl, let link = URL(string: url) {
                    Link(destination: link) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(pal.textPrimary)
                            .frame(width: 44, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func compactResultRow(_ result: RecognitionResult) -> some View {
        Button {
            playOnYouTubeMusic(result)
        } label: {
            HStack(spacing: 12) {
                SongThumb(url: result.coverArtHqUrl ?? result.coverArtUrl, size: 48, corner: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 15))
                        .foregroundStyle(pal.textPrimary)
                        .lineLimit(1)
                    Text(result.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(pal.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func playOnYouTubeMusic(_ result: RecognitionResult) {
        Task { @MainActor in
            if let song = try? await ShazamClient.playOnYouTubeMusic(result) {
                player.play(song, queue: [song], sourceName: "Recognition")
            }
        }
    }
}

// MARK: - Recognition history (RecognitionHistoryScreen.kt parity)

struct RecognitionHistoryView: View {
    @EnvironmentObject private var recognition: RecognitionManager
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Recognition history", showBack: true) {
                    Button {
                        recognition.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(pal.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                if recognition.history.isEmpty {
                    EmptyPlaceholder(icon: "clock.arrow.circlepath", text: "No recognitions yet.")
                } else {
                    ForEach(recognition.history) { result in
                        HStack(spacing: 12) {
                            SongThumb(url: result.coverArtHqUrl ?? result.coverArtUrl, size: 48, corner: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.system(size: 15))
                                    .foregroundStyle(pal.textPrimary)
                                    .lineLimit(1)
                                Text(result.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(pal.textSecondary)
                                    .lineLimit(1)
                                Text(Date(timeIntervalSince1970: result.recognizedAt), style: .date)
                                    .font(.system(size: 11))
                                    .foregroundStyle(pal.textSecondary.opacity(0.7))
                            }
                            Spacer()
                            Button {
                                Task { @MainActor in
                                    if let song = try? await ShazamClient.playOnYouTubeMusic(result) {
                                        player.play(song, queue: [song], sourceName: "Recognition")
                                    }
                                }
                            } label: {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(pal.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Spotify import screen (SpotifyImportScreen.kt parity)

struct SpotifyImportView: View {
    @EnvironmentObject private var spotify: SpotifyImporter
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var showLogin = false
    @State private var linkText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Import from Spotify", showBack: true) { EmptyView() }

                if !spotify.isSignedIn {
                    signInSection
                } else {
                    accountSection
                    if !spotify.sources.isEmpty {
                        sourcesSection
                    }
                }

                linkImportSection

                switch spotify.phase {
                case .loading:
                    HStack { Spacer(); ProgressView().padding(.vertical, 30); Spacer() }
                case .matching(let index, let total, let query):
                    VStack(spacing: 8) {
                        ProgressView(value: Double(index), total: Double(total))
                            .tint(pal.accent)
                        Text("Matching \(index)/\(total): \(query)")
                            .font(.system(size: 12))
                            .foregroundStyle(pal.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                case .done(let imported, let failed):
                    Text("Imported \(imported) songs" + (failed > 0 ? " (\(failed) unmatched)" : "") + " into your library.")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.horizontal, 16)
                case .error(let message):
                    ErrorBanner(message: message, onRetry: {
                        spotify.phase = .idle
                    })
                    .padding(16)
                default:
                    EmptyView()
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .sheet(isPresented: $showLogin) {
            WebLoginSheet(title: "Sign in to Spotify",
                          startUrl: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F",
                          desktopUserAgent: true,
                          shouldCapture: { url, _ in
                              url.host == "open.spotify.com"
                          },
                          onCookies: { cookies in
                              let spDc = cookies.first { $0.name == "sp_dc" }?.value ?? ""
                              let spKey = cookies.first { $0.name == "sp_key" }?.value ?? ""
                              if !spDc.isEmpty {
                                  spotify.spDc = spDc
                                  spotify.spKey = spKey
                                  Task { await spotify.loadSources() }
                              }
                          })
        }
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sign in to Spotify", systemImage: "music.note.list")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Text("Sign in with your Spotify account to import your playlists and liked songs. They are matched one-by-one against YouTube Music using weighted title, artist and duration similarity.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
            Button {
                showLogin = true
            } label: {
                Text("Sign in with Spotify")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(pal.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var accountSection: some View {
        SettingsGroup(title: "") {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(pal.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spotify.accountName.isEmpty ? "Signed in" : spotify.accountName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                    Text("sp_dc session active")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                }
                Spacer()
                Button {
                    spotify.signOut()
                } label: {
                    Text("Sign out")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pal.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            SettingsDivider()
            Button {
                Task { await spotify.loadSources() }
            } label: {
                SettingsNavRow(icon: "arrow.clockwise", title: "Reload playlists")
            }
            .buttonStyle(.plain)
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Your playlists")
            ForEach(spotify.sources) { source in
                HStack(spacing: 12) {
                    Image(systemName: source.isLikedSongs ? "heart.fill" : "music.note.list")
                        .font(.system(size: 20))
                        .foregroundStyle(pal.accent)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(pal.surface))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.system(size: 15))
                            .foregroundStyle(pal.textPrimary)
                            .lineLimit(1)
                        Text(source.isLikedSongs ? "Liked songs" : "\(source.trackCount) tracks")
                            .font(.system(size: 12))
                            .foregroundStyle(pal.textSecondary)
                    }
                    Spacer()
                    Button {
                        Task { await spotify.importSource(source: source) }
                    } label: {
                        Text("Import")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(pal.accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private var linkImportSection: some View {
        SettingsGroup(title: "Import from a link") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paste a public Spotify playlist link (open.spotify.com/playlist/… or spotify:playlist:…). Requires a signed-in session.")
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
                HStack(spacing: 10) {
                    TextField("https://open.spotify.com/playlist/…", text: $linkText)
                        .font(.system(size: 14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                    Button {
                        let link = linkText.trimmingCharacters(in: .whitespaces)
                        guard !link.isEmpty else { return }
                        Task { await spotify.importFromLink(link) }
                    } label: {
                        Text("Import")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(pal.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}
