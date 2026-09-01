import SwiftUI

/// Mini player — mirrors the Android FloatingMiniPlayer: thin progress line on
/// the top edge, artwork, marquee-style title, play/pause + next buttons.
struct MiniPlayerBar: View {
    var onTap: () -> Void

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.position / player.duration))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.surfaceHighest).frame(height: 2)
                    Capsule().fill(pal.accent).frame(width: max(2, geometry.size.width * progress), height: 2)
                }
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                SongThumb(url: player.currentSong?.thumbnailUrl, size: 42, corner: 8)

                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(text: player.currentSong?.title ?? "",
                                font: .system(size: 14, weight: .semibold),
                                color: pal.textPrimary)
                    Text(player.currentSong?.artistsText.isEmpty == false ? (player.currentSong?.artistsText ?? "") : "Unknown artist")
                        .font(.system(size: 11))
                        .foregroundStyle(pal.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(pal.surface))
                }
                .buttonStyle(.plain)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(pal.surface))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(pal.surface.opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(pal.surfaceHighest.opacity(0.6)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .padding(.bottom, 1)
    }
}

/// Marquee text — scrolls long titles like the Android player's BasicMarquee.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var animating = false

    var body: some View {
        let isLong = text.count > 28
        ZStack(alignment: .leading) {
            if isLong {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    Text(text + "   •   " + text + "   •   ")
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: animating ? -width : 0)
                        .animation(
                            animating
                                ? .linear(duration: Double(text.count) * 0.35).repeatForever(autoreverses: false)
                                : .default,
                            value: animating)
                }
                .frame(height: 20)
                .clipped()
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .onAppear {
            if isLong {
                animating = true
            }
        }
        .onChange(of: text) { _ in
            animating = text.count > 28
        }
    }
}
