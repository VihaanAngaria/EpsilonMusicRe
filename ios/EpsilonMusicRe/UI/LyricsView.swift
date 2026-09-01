import SwiftUI

/// Synced lyrics view — mirrors the Android player's lyrics panel:
/// auto-scrolling active line highlighting, tap-to-seek.
struct LyricsView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var lyrics: Lyrics?
    @State private var isLoading = true
    @State private var failed = false
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(lyrics?.sourceName ?? "Lyrics")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                Spacer()
                if isLoading {
                    ProgressView()
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
                                    : "Lyrics provided by LRCLIB when available.")
                Spacer()
            }
        }
        .task {
            guard lyrics == nil, let song = player.currentSong else { return }
            load(for: song)
        }
    }

    private func lyricsList(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        let active = activeIndex(lyrics) == index
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 20, weight: active ? .bold : .medium))
                            .foregroundStyle(active ? pal.accent : pal.textSecondary)
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

    private func activeIndex(_ lyrics: Lyrics) -> Int? {
        guard lyrics.isSynced else { return nil }
        return LyricsProvider.activeLineIndex(for: lyrics, position: player.position)
    }

    private func load(for song: Song) {
        isLoading = true
        failed = false
        Task { @MainActor in
            let result = await LyricsProvider.fetchLyrics(for: song)
            lyrics = result
            failed = (result == nil)
            isLoading = false
        }
    }
}
