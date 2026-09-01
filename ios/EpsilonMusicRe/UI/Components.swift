import SwiftUI

struct LogoMark: View {
    var size: CGFloat = 28
    var tint: Color = .epsTextPrimary

    var body: some View {
        Image("logo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(tint)
    }
}

struct ArtworkView: View {
    let song: Song?
    var side: CGFloat = 52
    var cornerRadius: CGFloat = 10

    var body: some View {
        if let image = song?.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.epsSurface)
                LogoMark(size: side * 0.5, tint: .epsTextSecondary)
            }
            .frame(width: side, height: side)
        }
    }
}

struct SongRow: View {
    @EnvironmentObject private var player: PlayerManager
    let song: Song
    let songs: [Song]
    var showsDuration: Bool = true

    var body: some View {
        Button {
            player.playSong(song, in: songs)
        } label: {
            HStack(spacing: 12) {
                ArtworkView(song: song, side: 48, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.epsTextPrimary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.epsTextSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if player.currentSong?.id == song.id {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.epsAccent)
                }
                if showsDuration {
                    Text(SongRow.format(song.duration))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(.epsTextSecondary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.epsAccent)
                .frame(width: 4, height: 18)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.epsTextPrimary)
            Spacer()
        }
    }
}
