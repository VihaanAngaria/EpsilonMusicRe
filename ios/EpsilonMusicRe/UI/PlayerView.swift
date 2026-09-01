import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    private let upNextCount = 5

    var body: some View {
        ZStack {
            Color.epsBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    artwork
                    meta
                    progress
                    controls
                    upNext
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            scrubValue = player.currentTime
        }
        .onChange(of: player.currentTime) { value in
            if !isScrubbing {
                scrubValue = value
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.epsTextPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.epsSurface))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Now Playing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.epsTextSecondary)
                .textCase(.uppercase)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    private var artwork: some View {
        ZStack {
            if let image = player.currentSong?.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.epsSurface
                LogoMark(size: 110, tint: .epsTextSecondary)
            }
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
        .padding(.top, 6)
    }

    private var meta: some View {
        VStack(spacing: 6) {
            Text(player.currentSong?.title ?? "Nothing playing")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.epsTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(player.currentSong?.artist ?? "")
                .font(.system(size: 15))
                .foregroundColor(.epsTextSecondary)
                .lineLimit(1)
        }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(
                value: $scrubValue,
                in: 0...max(player.duration, 0.1)
            ) { editing in
                isScrubbing = editing
                if !editing {
                    player.seek(to: scrubValue)
                }
            }
            .tint(.epsAccent)

            HStack {
                Text(SongRow.format(player.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.epsTextSecondary)
                Spacer()
                Text("-" + SongRow.format(max(0, player.duration - player.currentTime)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.epsTextSecondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 44) {
            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.epsTextPrimary)
            }
            .buttonStyle(.plain)

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 74, height: 74)
                    .background(Circle().fill(Color.epsAccent))
                    .shadow(color: Color.epsAccent.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(.plain)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.epsTextPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 12) {
            if player.queue.count > 1 {
                SectionHeader(title: "Up Next")
                ForEach(upNextSongs) { song in
                    Button {
                        if let index = player.queue.firstIndex(where: { $0.id == song.id }) {
                            player.playQueue(player.queue, startAt: index)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ArtworkView(song: song, side: 36, cornerRadius: 6)
                            Text(song.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.epsTextPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(song.artist)
                                .font(.system(size: 11))
                                .foregroundColor(.epsTextSecondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 10)
    }

    private var upNextSongs: [Song] {
        guard let index = player.currentIndex else { return [] }
        let rest = player.queue.dropFirst(index + 1)
        return Array(rest.prefix(upNextCount))
    }
}
