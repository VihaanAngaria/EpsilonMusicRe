import SwiftUI

/// Synced lyrics view — mirrors the Android player's lyrics panel:
/// provider-chain lyrics (YouLyPlus → Paxsenix → Unison → BetterLyrics →
/// SimpMusic → LRCLIB → KuGou → YouTube), auto-scrolling active line
/// highlighting, tap-to-seek, romanization and AI translation.
struct LyricsView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var ai: AIClient
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.epsPalette) private var pal

    @State private var lyrics: Lyrics?
    @State private var translatedLines: [String]?
    @State private var isTranslating = false
    @State private var isLoading = true
    @State private var failed = false
    @State private var autoScroll = true
    @State private var showRomanization = true
    @State private var loadedSongId: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(lyrics?.sourceName ?? "Lyrics")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                if isTranslating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Spacer()
                if lyrics != nil {
                    Button {
                        showRomanization.toggle()
                    } label: {
                        Image(systemName: "textformat.abc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(showRomanization && settings.romanizeLyrics ? pal.accent : pal.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        translate()
                    } label: {
                        Image(systemName: "translate")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(translatedLines != nil ? pal.accent : pal.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(pal.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(pal.surface))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if isLoading && lyrics == nil {
                Spacer()
                ProgressView()
                Spacer()
            } else if let lyrics = lyrics, !lyrics.lines.isEmpty {
                lyricsList(lyrics)
            } else {
                Spacer()
                EmptyPlaceholder(icon: "text.quote",
                                 text: failed
                                    ? "No lyrics found for this song."
                                    : "Lyrics from the provider chain (YouLyPlus, Paxsenix, Unison, BetterLyrics, SimpMusic, LRCLIB, KuGou, YouTube).")
                Spacer()
            }
        }
        .task(id: player.currentSong?.id) {
            guard let song = player.currentSong, loadedSongId != song.id else { return }
            load(for: song)
        }
    }

    private func lyricsList(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        let active = activeIndex(lyrics) == index
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayText(for: line))
                                .font(.system(size: 20, weight: active ? .bold : .medium))
                                .foregroundStyle(active ? pal.accent : pal.textSecondary)
                            if let translated = translatedLines, index < translated.count, !translated[index].isEmpty, translated[index] != line.text {
                                Text(translated[index])
                                    .font(.system(size: 14))
                                    .foregroundStyle(active ? pal.textSecondary : pal.textSecondary.opacity(0.6))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if lyrics.isSynced, line.time >= 0 {
                                autoScroll = false
                                player.seek(to: line.time)
                                // Resume auto-scroll shortly after a manual jump.
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                                    autoScroll = true
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: 120).id("bottom")
                }
                .padding(.vertical, 12)
            }
            .onChange(of: player.position) { _ in
                guard autoScroll, lyrics.isSynced, let active = activeIndex(lyrics) else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(active, anchor: .center)
                }
            }
        }
    }

    /// Romanized text under the setting (LyricsUtils.kt parity).
    private func displayText(for line: LyricsLine) -> String {
        let text = line.text.isEmpty ? "♪" : line.text
        guard settings.romanizeLyrics, showRomanization else { return text }
        let romanized = Romanization.romanize(text)
        return romanized == text ? text : romanized
    }

    private func activeIndex(_ lyrics: Lyrics) -> Int? {
        guard lyrics.isSynced else { return nil }
        return LyricsAggregator.activeLineIndex(for: lyrics, position: player.position)
    }

    private func load(for song: Song) {
        loadedSongId = song.id
        isLoading = true
        failed = false
        translatedLines = nil
        Task { @MainActor in
            let result = await LyricsAggregator.fetchLyrics(for: song)
            lyrics = result
            failed = (result == nil)
            isLoading = false
            if settings.autoTranslateLyrics, result != nil {
                translate()
            }
        }
    }

    private func translate() {
        guard let lyrics = lyrics, translatedLines == nil, !isTranslating,
              let song = player.currentSong, !song.isLocal else { return }
        isTranslating = true
        Task { @MainActor in
            defer { isTranslating = false }
            guard ai.isConfigured else { return }
            let lines = lyrics.lines.map(\.text)
            if let translated = try? await ai.translateLyrics(lines: lines) {
                translatedLines = translated
            }
        }
    }
}

extension LyricsAggregator {
    static func activeLineIndex(for lyrics: Lyrics, position: Double) -> Int? {
        guard lyrics.isSynced, !lyrics.lines.isEmpty else { return nil }
        var active: Int? = nil
        for (index, line) in lyrics.lines.enumerated() {
            if line.time >= 0, line.time <= position + 0.25 {
                active = index
            } else if line.time > position {
                break
            }
        }
        return active
    }
}
