import SwiftUI

// MARK: - Listen Together tab (ListenTogetherScreen.kt parity — real client)

struct ListenTogetherView: View {
    @EnvironmentObject private var lt: ListenTogetherClient
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var username = ""
    @State private var joinCode = ""
    @State private var chatText = ""
    @State private var showServerPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    NavigationTitleBar(title: "Listen Together") {
                        Button {
                            showServerPicker = true
                        } label: {
                            Image(systemName: "server.rack")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(pal.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    switch lt.phase {
                    case .idle, .connecting:
                        setupContent
                    case .awaitingApproval(let code):
                        awaitingApprovalCard(code: code)
                    case .inRoom(let code):
                        roomContent(code: code)
                    case .error(let message):
                        errorCard(message)
                    }
                    Color.clear.frame(height: 96)
                }
            }
            .background(pal.background.ignoresSafeArea())
            .sheet(isPresented: $showServerPicker) {
                ServerPickerSheet()
                    .presentationDetents([.medium])
            }
            .onAppear {
                username = lt.username
            }
        }
    }

    // MARK: Setup

    private var setupContent: some View {
        VStack(spacing: 16) {
            if case .connecting = lt.phase {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Connecting…")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Your name", systemImage: "person.crop.circle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                TextField("Display name", text: $username)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                    .onChange(of: username) { newValue in
                        lt.username = newValue
                    }
                Button {
                    lt.createRoom()
                } label: {
                    Label("Create room", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(pal.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))

            VStack(alignment: .leading, spacing: 10) {
                Label("Join a room", systemImage: "person.2.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                HStack(spacing: 10) {
                    TextField("Room code", text: $joinCode)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                    Button {
                        let code = joinCode.trimmingCharacters(in: .whitespaces)
                        guard !code.isEmpty else { return }
                        lt.joinRoom(code: code)
                    } label: {
                        Text("Join")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(pal.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
            .padding(.horizontal, 16)

            howItWorksCard
        }
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How it works", systemImage: "info.circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Text("Everyone in the room hears the same track at the same position. The host controls playback; participants can suggest tracks and chat. Buffers are synchronized before each track starts.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 0)
    }

    // MARK: Awaiting approval

    private func awaitingApprovalCard(code: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 34))
                .foregroundStyle(pal.accent)
            Text("Waiting for host approval")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
            Text("You asked to join room \(code). The host needs to approve your request.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                lt.disconnect()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pal.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: In-room

    private func roomContent(code: String) -> some View {
        VStack(spacing: 16) {
            roomHeader(code: code)
            if lt.isHost {
                pendingJoinsSection
            }
            nowPlayingSync
            membersSection
            suggestionsSection
            chatSection
        }
        .padding(.horizontal, 16)
    }

    private func roomHeader(code: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Room \(code)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(pal.textPrimary)
                    Text(lt.isHost ? "You are the host" : "Guest")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.accent)
                }
                Spacer()
                Button {
                    lt.leave()
                } label: {
                    Text("Leave")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(pal.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(pal.accent.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
    }

    private var nowPlayingSync: some View {
        Group {
            if let track = lt.roomState?.currentTrack {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        SongThumb(url: track.thumbnail, size: 64, corner: 10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(pal.textPrimary)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(pal.textSecondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Image(systemName: lt.roomState?.isPlaying == true ? "speaker.wave.2.fill" : "pause.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(pal.accent)
                                Text(lt.roomState?.isPlaying == true ? "Playing together" : "Paused")
                                    .font(.system(size: 11))
                                    .foregroundStyle(pal.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    // Sync controls — host always; guests if allowed.
                    if lt.isHost || lt.roomState?.allowParticipantControl == true {
                        HStack(spacing: 12) {
                            Button {
                                lt.sendPlaybackAction(.skipPrev)
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(pal.textPrimary)
                            }
                            .buttonStyle(.plain)
                            Button {
                                let playing = lt.roomState?.isPlaying == true
                                lt.sendPlaybackAction(playing ? .pause : .play)
                            } label: {
                                Image(systemName: lt.roomState?.isPlaying == true ? "pause.fill" : "play.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(Circle().fill(pal.accent))
                            }
                            .buttonStyle(.plain)
                            Button {
                                lt.sendPlaybackAction(.skipNext)
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(pal.textPrimary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                suggestCurrentSong()
                            } label: {
                                Label("Suggest current", systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(pal.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundStyle(pal.textSecondary)
                    Text("Nothing playing — the host can queue a song.")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                    if lt.isHost, let song = player.currentSong {
                        Button {
                            lt.sendPlaybackAction(.changeTrack, track: Song.toTrackInfo(song))
                        } label: {
                            Label("Play current song for everyone", systemImage: "play.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(pal.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
            }
        }
    }

    private func suggestCurrentSong() {
        guard let song = player.currentSong else { return }
        lt.suggestTrack(song)
    }

    private var pendingJoinsSection: some View {
        Group {
            if !lt.pendingJoins.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Join requests")
                    ForEach(lt.pendingJoins) { user in
                        HStack {
                            Image(systemName: "person.crop.circle.badge.clock")
                                .foregroundStyle(pal.accent)
                            Text(user.username)
                                .font(.system(size: 14))
                                .foregroundStyle(pal.textPrimary)
                            Spacer()
                            Button {
                                lt.approveJoin(userId: user.userId)
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            Button {
                                lt.rejectJoin(userId: user.userId)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "In the room (\(lt.roomState?.users.count ?? 0))")
            ForEach(lt.roomState?.users ?? []) { user in
                HStack(spacing: 10) {
                    Image(systemName: user.isHost ? "crown.fill" : "person.crop.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(user.isHost ? pal.accent : pal.textSecondary)
                    Text(user.username + (user.userId == ltUserId ? " (you)" : ""))
                        .font(.system(size: 14))
                        .foregroundStyle(pal.textPrimary)
                    if !user.isConnected {
                        Text("offline")
                            .font(.system(size: 11))
                            .foregroundStyle(pal.textSecondary)
                    }
                    Spacer()
                    if lt.isHost && !user.isHost {
                        Menu {
                            Button {
                                lt.transferHost(to: user.userId)
                            } label: {
                                Label("Make host", systemImage: "crown")
                            }
                            Button(role: .destructive) {
                                lt.kickUser(userId: user.userId)
                            } label: {
                                Label("Remove", systemImage: "person.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pal.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            if lt.isHost {
                Toggle("Allow participants to control playback", isOn: Binding(
                    get: { lt.roomState?.allowParticipantControl ?? true },
                    set: { lt.setRoomSettings(allowParticipantControl: $0) }))
                    .font(.system(size: 13))
                    .tint(pal.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
    }

    private var ltUserId: String? {
        // Internal user id — exposed via KVC-free helper.
        nil
    }

    private var suggestionsSection: some View {
        Group {
            if !lt.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Suggestions")
                    ForEach(lt.suggestions) { suggestion in
                        HStack(spacing: 12) {
                            SongThumb(url: suggestion.track.thumbnail, size: 44, corner: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.track.title)
                                    .font(.system(size: 14))
                                    .foregroundStyle(pal.textPrimary)
                                    .lineLimit(1)
                                Text("by \(suggestion.suggestedBy)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(pal.textSecondary)
                            }
                            Spacer()
                            if lt.isHost {
                                Button {
                                    lt.approveSuggestion(suggestion)
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 18))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    lt.rejectSuggestion(suggestion)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 18))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
            }
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Chat")
            if lt.chat.isEmpty {
                Text("No messages yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
                    .padding(.horizontal, 16)
            } else {
                ForEach(lt.chat.suffix(30)) { message in
                    HStack(alignment: .top, spacing: 8) {
                        if message.isSystem {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11))
                                .foregroundStyle(pal.textSecondary)
                        } else {
                            Text(message.username.prefix(1).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(message.isHost ? pal.accent : pal.surfaceHighest))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.isSystem ? "" : message.username)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(message.isHost ? pal.accent : pal.textSecondary)
                            Text(message.message)
                                .font(.system(size: 14))
                                .foregroundStyle(pal.textPrimary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                }
            }
            HStack(spacing: 10) {
                TextField("Message", text: $chatText)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                    .onSubmit {
                        lt.sendChat(chatText)
                        chatText = ""
                    }
                Button {
                    lt.sendChat(chatText)
                    chatText = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(pal.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(pal.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                lt.phase = .idle
            } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pal.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Server picker (server.json list)

struct ServerPickerSheet: View {
    @EnvironmentObject private var lt: ListenTogetherClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal

    @State private var servers: [LTServers.ServerEntry] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(servers) { server in
                        Button {
                            LTServers.selectedUrl = server.serverUrl
                            lt.disconnect()
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .foregroundStyle(pal.textPrimary)
                                Text(server.serverUrl)
                                    .font(.system(size: 11))
                                    .foregroundStyle(pal.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text(LTServers.selectedUrl == servers.first?.serverUrl ? "Current server" : "Servers")
                }
            }
            .navigationTitle("Listen Together server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            servers = await LTServers.fetchServers()
        }
    }
}

extension Song {
    static func toTrackInfo(_ song: Song) -> LTTrackInfo {
        LTTrackInfo(id: song.id, title: song.title, artist: song.artistsText,
                    album: song.album, duration: song.duration ?? 0,
                    thumbnail: song.thumbnailUrl, suggestedBy: nil)
    }
}
