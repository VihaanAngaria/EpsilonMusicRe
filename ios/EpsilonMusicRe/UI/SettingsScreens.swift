import SwiftUI

// MARK: - Appearance settings (AppearanceSettings + ThemeScreen + GlassEffect parity)

struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Appearance", showBack: true) { EmptyView() }

                SettingsGroup(title: "Theme") {
                    ForEach(ThemeMode.allCases) { mode in
                        Button {
                            settings.themeMode = mode
                        } label: {
                            SettingsNavRow(icon: mode.icon, title: mode.title,
                                           subtitle: settings.themeMode == mode ? "Selected" : nil)
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    SettingsToggleRow(icon: "moon.stars.fill",
                                      title: "Pure black",
                                      subtitle: "True black background (AMOLED)",
                                      isOn: Binding(get: { settings.pureBlack }, set: { settings.pureBlack = $0 }))
                }

                SettingsGroup(title: "Dynamic theming") {
                    SettingsToggleRow(icon: "paintpalette.fill",
                                      title: "Dynamic theme",
                                      subtitle: "Tint the app with colors from the current artwork (MaterialKolor)",
                                      isOn: Binding(get: { settings.dynamicTheme }, set: { settings.dynamicTheme = $0 }))
                }

                SettingsGroup(title: "Accent color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 14) {
                        ForEach(AppSettings.accentOptions) { option in
                            Button {
                                settings.accentHex = option.hex
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 44, height: 44)
                                    if settings.accentHex == option.hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }

                SettingsGroup(title: "Player look") {
                    Picker("Player background", selection: Binding(
                        get: { settings.playerBackgroundStyle },
                        set: { settings.playerBackgroundStyle = $0 })) {
                        ForEach(PlayerBackgroundStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    SettingsDivider()
                    SettingsToggleRow(icon: "disc",
                                      title: "Rotating artwork",
                                      subtitle: "Spin the album art while playing",
                                      isOn: Binding(get: { settings.rotatingThumbnail }, set: { settings.rotatingThumbnail = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "square.stack.3d.up",
                                      title: "Canvas animated artwork",
                                      subtitle: "Looping motion artwork from Apple Music when available",
                                      isOn: Binding(get: { settings.canvasThumbnail }, set: { settings.canvasThumbnail = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "waveform.path",
                                      title: "Wavy slider",
                                      subtitle: "Squiggly progress slider in the player",
                                      isOn: Binding(get: { settings.wavySlider }, set: { settings.wavySlider = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "textformat",
                                      title: "Show codec info",
                                      subtitle: "Codec, bitrate and sample rate on the player",
                                      isOn: Binding(get: { settings.showCodecOnPlayer }, set: { settings.showCodecOnPlayer = $0 }))
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

extension ThemeMode {
    var icon: String {
        switch self {
        case .system: return "gearshape"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Player & audio settings (PlayerSettings.kt parity)

struct PlayerSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var eq: EqualizerEngine
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Player and audio", showBack: true) { EmptyView() }

                SettingsGroup(title: "Equalizer") {
                    NavigationLink {
                        EqualizerView()
                    } label: {
                        SettingsNavRow(icon: "slider.vertical.3", title: "Equalizer",
                                       subtitle: "10-band EQ with presets")
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: "Playback") {
                    SettingsToggleRow(icon: "infinity",
                                      title: "Audio normalization",
                                      subtitle: "Normalize loudness using each stream's loudness data",
                                      isOn: Binding(get: { eq.normalizationEnabled }, set: { eq.normalizationEnabled = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "waveform.slash",
                                      title: "Skip silence",
                                      subtitle: "Hop 15 s over long silent passages",
                                      isOn: Binding(get: { eq.skipSilence }, set: { eq.skipSilence = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "arrow.triangle.2.circlepath",
                                      title: "Persistent queue",
                                      subtitle: "Restore the queue after the app restarts",
                                      isOn: Binding(get: { eq.persistentQueue }, set: { eq.persistentQueue = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "dot.radiowaves.left.and.right",
                                      title: "Autoplay similar songs",
                                      subtitle: "Continue with a radio mix when the queue ends",
                                      isOn: Binding(get: { settings.autoplayRelated }, set: { settings.autoplayRelated = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "exclamationmark.arrow.triangle.2.circlepath",
                                      title: "Skip on stream error",
                                      subtitle: "Automatically jump to the next song when playback fails",
                                      isOn: Binding(get: { settings.skipOnStreamError }, set: { settings.skipOnStreamError = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "heart.arrow.circlepath",
                                      title: "Auto-download on like",
                                      subtitle: "Download songs when you like them",
                                      isOn: Binding(get: { settings.autoDownloadOnLike }, set: { settings.autoDownloadOnLike = $0 }))
                }

                SettingsGroup(title: "Crossfade (Beta)") {
                    SettingsToggleRow(icon: "arrow.left.arrow.right.circle",
                                      title: "Crossfade",
                                      subtitle: "Equal-power fade between consecutive tracks",
                                      isOn: Binding(get: { eq.crossfadeEnabled }, set: { eq.crossfadeEnabled = $0 }))
                    if eq.crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Duration")
                                    .font(.system(size: 14))
                                    .foregroundStyle(pal.textPrimary)
                                Spacer()
                                Text("\(Int(eq.crossfadeDuration)) s")
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(pal.textSecondary)
                            }
                            Slider(value: Binding(
                                get: { eq.crossfadeDuration },
                                set: { eq.crossfadeDuration = $0 }), in: 1...15, step: 1)
                                .tint(pal.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }

                SettingsGroup(title: "Lyrics") {
                    SettingsToggleRow(icon: "text.book.closed",
                                      title: "Show romanized lyrics",
                                      subtitle: "Romanize Korean, Japanese, Cyrillic, Devanagari and Gurmukhi lines",
                                      isOn: Binding(get: { settings.romanizeLyrics }, set: { settings.romanizeLyrics = $0 }))
                    SettingsDivider()
                    NavigationLink {
                        RomanizationSettingsView()
                    } label: {
                        SettingsNavRow(icon: "textformat.abc", title: "Romanization", subtitle: "Per-script toggles")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    SettingsToggleRow(icon: "translate",
                                      title: "Auto-translate lyrics",
                                      subtitle: "Translate with the AI provider as lyrics load",
                                      isOn: Binding(get: { settings.autoTranslateLyrics }, set: { settings.autoTranslateLyrics = $0 }))
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Romanization settings (RomanizationSettings.kt parity)

struct RomanizationSettingsView: View {
    @Environment(\.epsPalette) private var pal

    @AppStorage("lyricsRomanizeJapanese") private var japanese = true
    @AppStorage("lyricsRomanizeKorean") private var korean = true
    @AppStorage("lyricsRomanizeCyrillic") private var cyrillic = true
    @AppStorage("lyricsRomanizeHindi") private var hindi = true
    @AppStorage("lyricsRomanizePunjabi") private var punjabi = true
    @AppStorage("lyricsRomanizeAsMain") private var asMain = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Romanization", showBack: true) { EmptyView() }
                SettingsGroup(title: "General") {
                    SettingsToggleRow(icon: "textformat.abc", title: "Japanese (kana)", isOn: $japanese)
                    SettingsDivider()
                    SettingsToggleRow(icon: "textformat.abc", title: "Korean (Hangul)", isOn: $korean)
                    SettingsDivider()
                    SettingsToggleRow(icon: "textformat.abc", title: "Cyrillic", isOn: $cyrillic)
                    SettingsDivider()
                    SettingsToggleRow(icon: "textformat.abc", title: "Hindi (Devanagari)", isOn: $hindi)
                    SettingsDivider()
                    SettingsToggleRow(icon: "textformat.abc", title: "Punjabi (Gurmukhi)", isOn: $punjabi)
                    SettingsDivider()
                    SettingsToggleRow(icon: "textformat.abc",
                                      title: "Show romanization as main line",
                                      subtitle: "Display romanized text instead of the original",
                                      isOn: $asMain)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - AI settings (AiSettings.kt parity)

struct AISettingsView: View {
    @EnvironmentObject private var ai: AIClient
    @Environment(\.epsPalette) private var pal

    @State private var key = ""
    @State private var model = ""
    @State private var deeplKey = ""
    @State private var language = "en"
    @State private var savedTick = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "AI lyrics translation", showBack: true) { EmptyView() }

                SettingsGroup(title: "Provider") {
                    Picker("Provider", selection: Binding(
                        get: { ai.provider },
                        set: { ai.provider = $0; ai.baseUrl = ai.defaultBaseUrl })) {
                        Text("OpenRouter").tag("OpenRouter")
                        Text("Mistral").tag("Mistral")
                        Text("DeepL").tag("DeepL")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if ai.provider != "DeepL" {
                    SettingsGroup(title: "OpenAI-compatible settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API key")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(pal.textSecondary)
                            SecureField("sk-or-v1-…", text: $key)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            Text("Model")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(pal.textSecondary)
                            TextField("google/gemini-2.5-flash-lite", text: $model)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            Button {
                                ai.apiKey = key.trimmingCharacters(in: .whitespaces)
                                ai.model = model.trimmingCharacters(in: .whitespaces)
                                savedTick.toggle()
                            } label: {
                                Label("Save", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(pal.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                    }
                } else {
                    SettingsGroup(title: "DeepL") {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("DeepL-Auth-Key", text: $deeplKey)
                                .font(.system(size: 14, design: .monospaced))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            Button {
                                ai.deeplKey = deeplKey.trimmingCharacters(in: .whitespaces)
                            } label: {
                                Label("Save", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(pal.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                    }
                }

                SettingsGroup(title: "Translation") {
                    Picker("Mode", selection: Binding(
                        get: { ai.translationMode },
                        set: { ai.translationMode = $0 })) {
                        Text("Literal").tag("Literal")
                        Text("Romanized").tag("Romanized")
                        Text("Transcribed").tag("Transcribed")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    SettingsDivider()
                    HStack {
                        Text("Target language")
                            .font(.system(size: 15))
                            .foregroundStyle(pal.textPrimary)
                        Spacer()
                        TextField("en", text: $language)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .autocorrectionDisabled()
                        Button("Save") {
                            ai.translationLanguage = language.trimmingCharacters(in: .whitespaces)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pal.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    SettingsDivider()
                    SettingsToggleRow(icon: "wand.and.stars",
                                      title: "Auto-translate",
                                      subtitle: "Translate lyrics automatically when they load",
                                      isOn: Binding(get: { ai.autoTranslate }, set: { ai.autoTranslate = $0 }))
                    SettingsDivider()
                    SettingsToggleRow(icon: "sparkles",
                                      title: "AI recommendations",
                                      subtitle: "Weekly recommended playlist from your listening history",
                                      isOn: Binding(get: { ai.aiRecommendations }, set: { ai.aiRecommendations = $0 }))
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .onAppear {
            key = ai.apiKey
            model = ai.model
            deeplKey = ai.deeplKey
            language = ai.translationLanguage
        }
    }
}

// MARK: - Content settings (ContentSettings.kt parity)

struct ContentSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Content", showBack: true) { EmptyView() }
                SettingsGroup(title: "On-device music") {
                    SettingsToggleRow(icon: "iphone",
                                      title: "Hide on-device songs in search",
                                      subtitle: "Keep results to YouTube Music only",
                                      isOn: Binding(get: { settings.hideLocalInSearch }, set: { settings.hideLocalInSearch = $0 }))
                    SettingsDivider()
                    Button {
                        library.loadLocalSongs()
                    } label: {
                        SettingsNavRow(icon: "arrow.clockwise", title: "Rescan device library")
                    }
                    .buttonStyle(.plain)
                }
                SettingsGroup(title: "History") {
                    Button {
                        library.clearHistory()
                    } label: {
                        SettingsNavRow(icon: "clock.badge.xmark", title: "Clear play history", subtitle: "Removes all local listening events")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    Button {
                        library.clearSearchHistory()
                    } label: {
                        SettingsNavRow(icon: "magnifyingglass", title: "Clear search history")
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Privacy settings (PrivacySettings.kt parity)

struct PrivacySettingsView: View {
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Privacy", showBack: true) { EmptyView() }
                SettingsGroup(title: "Data") {
                    SettingsValueRow(icon: "hand.raised.fill", title: "Telemetry", value: "None")
                    SettingsDivider()
                    SettingsValueRow(icon: "lock.shield", title: "Analytics", value: "Disabled")
                    SettingsDivider()
                    Text("Epsilon Music does not collect or share any personal data. All preferences, history and playlists stay on your device. Sign-in credentials for YouTube, Discord, Spotify and scrobbling services are stored only in your local settings and sent directly to those services.")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

// MARK: - Storage settings (StorageSettings.kt parity)

struct StorageSettingsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    @State private var downloadBytes: Int64 = 0
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Storage", showBack: true) { EmptyView() }

                SettingsGroup(title: "Downloads") {
                    SettingsValueRow(icon: "arrow.down.circle.fill",
                                     title: "Downloaded songs",
                                     value: ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file))
                    SettingsDivider()
                    SettingsValueRow(icon: "music.note",
                                     title: "Song count",
                                     value: "\(downloads.downloadedSongs().count) songs")
                    SettingsDivider()
                    Button {
                        showClearConfirm = true
                    } label: {
                        SettingsNavRow(icon: "trash", title: "Clear all downloads",
                                       subtitle: "Removes offline copies; streams re-download on play")
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: "Caches") {
                    Button {
                        downloads.clearSongCache()
                    } label: {
                        SettingsNavRow(icon: "tray.full", title: "Clear song cache")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    Button {
                        downloads.clearImageCache()
                    } label: {
                        SettingsNavRow(icon: "photo.stack", title: "Clear image cache")
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .onAppear { downloadBytes = downloads.totalSizeBytes() }
        .alert("Clear all downloads?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                downloads.removeAll()
                downloadBytes = downloads.totalSizeBytes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Offline copies are removed from this device. Library entries are kept.")
        }
    }
}

// MARK: - Backup & restore (BackupAndRestore.kt parity)

struct BackupRestoreView: View {
    @Environment(\.epsPalette) private var pal

    @State private var resultText: String?
    @State private var showImporter = false
    @State private var backupUrl: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Backup and restore", showBack: true) { EmptyView() }

                SettingsGroup(title: "Backup") {
                    Button {
                        if let url = BackupRestore.export() {
                            backupUrl = url
                            resultText = "Backup saved: \(url.lastPathComponent)"
                        } else {
                            resultText = "Backup failed"
                        }
                    } label: {
                        SettingsNavRow(icon: "externaldrive.badge.timemachine",
                                       title: "Export settings and library",
                                       subtitle: "JSON backup with playlists, history and preferences")
                    }
                    .buttonStyle(.plain)
                    if let backupUrl = backupUrl {
                        ShareLink(item: backupUrl) {
                            SettingsNavRow(icon: "square.and.arrow.up",
                                           title: "Share the backup file",
                                           subtitle: backupUrl.lastPathComponent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                SettingsGroup(title: "Restore") {
                    Button {
                        showImporter = true
                    } label: {
                        SettingsNavRow(icon: "arrow.uturn.down.circle",
                                       title: "Import backup",
                                       subtitle: "Pick an epsilonmusic-backup.json file")
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: "Playlist import") {
                    NavigationLink {
                        SpotifyImportView()
                    } label: {
                        SettingsNavRow(icon: "music.note.list", title: "Import from Spotify")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    NavigationLink {
                        CSVImportView()
                    } label: {
                        SettingsNavRow(icon: "doc.plaintext", title: "Import playlists (CSV / M3U)")
                    }
                    .buttonStyle(.plain)
                }

                if let resultText = resultText {
                    Text(resultText)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let secured = url.startAccessingSecurityScopedResource()
                let ok = BackupRestore.restore(from: url)
                if secured { url.stopAccessingSecurityScopedResource() }
                resultText = ok ? "Restored backup — restart the app to apply all settings." : "Restore failed — not a valid backup."
            }
        }
    }
}

// MARK: - CSV / M3U playlist import (Android CSV importer parity)

struct CSVImportView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var playlistName = ""
    @State private var rows: [(artist: String, title: String)] = []
    @State private var statusText: String?
    @State private var showImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Import playlists", showBack: true) { EmptyView() }
                SettingsGroup(title: "CSV / M3U") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pick a .csv file with Artist,Title columns (header row detected) or an .m3u file with #EXTINF lines. Tracks are matched on YouTube Music.")
                            .font(.system(size: 13))
                            .foregroundStyle(pal.textSecondary)
                        TextField("Playlist name", text: $playlistName)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                        Button {
                            showImporter = true
                        } label: {
                            Label("Choose file", systemImage: "folder")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pal.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
                if !rows.isEmpty {
                    SettingsGroup(title: "\(rows.count) tracks found") {
                        Button {
                            matchAndCreate()
                        } label: {
                            SettingsNavRow(icon: "arrow.right.circle.fill", title: "Match on YouTube Music and create")
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let statusText = statusText {
                    Text(statusText)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .commaSeparatedText]) { result in
            guard case .success(let url) = result else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                rows = Self.parse(text: text)
                if playlistName.isEmpty {
                    playlistName = url.deletingPathExtension().lastPathComponent
                }
                statusText = rows.isEmpty ? "No tracks detected." : nil
            }
        }
    }

    static func parse(text: String) -> [(artist: String, title: String)] {
        var out: [(String, String)] = []
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF:") {
                // #EXTINF:duration,Artist - Title
                let parts = line.dropFirst("#EXTINF:".count).components(separatedBy: ",", maxSplits: 1)
                if parts.count == 2 {
                    let entry = parts[1]
                    if let dash = entry.range(of: " - ") {
                        out.append((String(entry[entry.startIndex..<dash.lowerBound]).trimmingCharacters(in: .whitespaces),
                                    String(entry[dash.upperBound...]).trimmingCharacters(in: .whitespaces)))
                    } else {
                        out.append(("", entry))
                    }
                }
            } else if line.hasPrefix("#") || line.isEmpty {
                continue
            } else if line.contains(",") && !line.hasPrefix("http") {
                let parts = line.components(separatedBy: ",")
                if parts.count >= 2 {
                    let isHeader = index == 0 && (parts[0].lowercased().contains("artist") || parts[1].lowercased().contains("title"))
                    if !isHeader {
                        // artist,title order; tolerate title,artist
                        if parts[1].lowercased().contains("http") {
                            out.append((parts[0], ""))
                        } else {
                            out.append((parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces)))
                        }
                    }
                }
            }
        }
        return out.filter { !$0.title.isEmpty || !$0.artist.isEmpty }
    }

    private func matchAndCreate() {
        let tracks = rows
        let name = playlistName.isEmpty ? "Imported playlist" : playlistName
        statusText = "Matching 0/\(tracks.count)…"
        Task { @MainActor in
            var songs: [Song] = []
            for (index, track) in tracks.enumerated() {
                statusText = "Matching \(index + 1)/\(tracks.count): \(track.title)"
                let query = [track.artist, track.title].filter { !$0.isEmpty }.joined(separator: " ")
                if let result = try? await InnerTube.shared.search(query: query, filter: .songs),
                   let song = result.songs.first {
                    songs.append(song)
                }
            }
            if !songs.isEmpty {
                _ = library.createPlaylist(named: name, songs: songs)
                statusText = "Created \"\(name)\" with \(songs.count) of \(tracks.count) tracks."
            } else {
                statusText = "No tracks could be matched."
            }
        }
    }
}

// MARK: - Update settings (UpdateSettings.kt parity)

struct UpdateSettingsView: View {
    @EnvironmentObject private var updater: Updater
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "System update", showBack: true) { EmptyView() }
                SettingsGroup(title: "Updates") {
                    SettingsToggleRow(icon: "arrow.triangle.2.circlepath",
                                      title: "Check automatically",
                                      subtitle: "Look for new releases on launch",
                                      isOn: Binding(get: { updater.autoCheck }, set: { updater.autoCheck = $0 }))
                    SettingsDivider()
                    Button {
                        Task { await updater.checkForUpdates() }
                    } label: {
                        SettingsNavRow(icon: "arrow.down.circle", title: "Check now",
                                       subtitle: "Current version: \(updater.currentVersion)")
                    }
                    .buttonStyle(.plain)
                }
                if updater.isChecking {
                    HStack { Spacer(); ProgressView().padding(.vertical, 20); Spacer() }
                }
                if let error = updater.lastError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.horizontal, 16)
                }
                if let info = updater.updateInfo {
                    updateCard(info)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task {
            if updater.autoCheck, updater.updateInfo == nil {
                await updater.checkForUpdates()
            }
        }
    }

    @ViewBuilder
    private func updateCard(_ info: Updater.UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Version \(info.version)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                Spacer()
            }
            ForEach(Array(info.changelog.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(pal.accent)
                    }
                    ForEach(section.items, id: \.self) { item in
                        Text("• \(item)")
                            .font(.system(size: 13))
                            .foregroundStyle(pal.textSecondary)
                    }
                }
            }
            if let url = info.downloadUrl, let url = URL(string: url) {
                Link(destination: url) {
                    Text("Get the update")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(pal.accent))
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - About (AboutScreen.kt parity)

struct AboutView: View {
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "About", showBack: true) { EmptyView() }
                VStack(spacing: 12) {
                    SongThumb(url: nil, size: 96, corner: 24)
                    Text("Epsilon Music")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(pal.textPrimary)
                    Text("Version \(Updater.shared.currentVersion)")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                    Text("A full-featured YouTube Music client for iOS with every Android feature: streaming, downloads, synced lyrics with romanization and AI translation, a 10-band equalizer, crossfade, Listen Together, music recognition, scrobbling, Discord presence and Spotify import.")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                SettingsGroup(title: "Links") {
                    if let url = URL(string: "https://github.com/VihaanAngaria/EpsilonMusicRe") {
                        Link(destination: url) {
                            SettingsNavRow(icon: "safari", title: "GitHub repository")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if let url = URL(string: "https://github.com/VihaanAngaria/EpsilonMusicRe/issues") {
                        Link(destination: url) {
                            SettingsNavRow(icon: "ladybug", title: "Report an issue")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    SettingsValueRow(icon: "person.2", title: "Contributors", value: "Vihaan Angaria & the Epsilon community")
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}
