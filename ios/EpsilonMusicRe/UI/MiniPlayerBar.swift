import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerManager
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkView(song: player.currentSong, side: 44, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentSong?.title ?? "")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.epsTextPrimary)
                        .lineLimit(1)
                    Text(player.currentSong?.artist ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.epsTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.epsTextPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.epsSurface)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
            )
            .overlay(alignment: .top) { progressBar }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.epsTextSecondary.opacity(0.3))
                Capsule()
                    .fill(Color.epsAccent)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 12)
    }

    private var fraction: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(player.currentTime / player.duration, 1))
    }
}
