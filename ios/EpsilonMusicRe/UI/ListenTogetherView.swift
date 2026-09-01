import SwiftUI

/// Listen Together tab — replicates the Android ListenTogetherScreen layout.
/// The Listen Together host protocol currently runs on the Android edition;
/// this screen keeps the tab structure identical and documents the state.
struct ListenTogetherView: View {
    @Environment(\.epsPalette) private var pal

    @State private var joinCode = ""
    @State private var showJoinAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    NavigationTitleBar(title: "Listen Together") {
                        EmptyView()
                    }

                    hostCard
                    joinCard
                    howItWorksCard

                    Color.clear.frame(height: 96)
                }
            }
            .background(pal.background.ignoresSafeArea())
            .alert("Join room", isPresented: $showJoinAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Listen Together sessions are hosted from the Android edition of Epsilon Music today. Joining a room from iOS requires the sync server, which is coming to iOS in a follow-up release.")
            }
        }
    }

    private var hostCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Create a room", systemImage: "antenna.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Text("Host a synchronized listening session. Everyone in the room hears the same track at the same time, with in-sync chat.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
            Button {
                showJoinAlert = true
            } label: {
                Text("Create room")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(pal.surfaceHighest))
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Join a room", systemImage: "person.2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Text("Have a room code from a friend? Enter it below.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
            HStack(spacing: 10) {
                TextField("Room code", text: $joinCode)
                    .font(.system(size: 15))
                    .foregroundStyle(pal.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button {
                    showJoinAlert = true
                } label: {
                    Text("Join")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(pal.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("About Listen Together", systemImage: "info.circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Text("The host device runs a small sync server and shares a code. Playback position, play/pause and the current queue stay synchronized across every listener. The Android edition is fully supported today; iOS support is planned on the same protocol.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
