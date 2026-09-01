import SwiftUI
import WebKit

// MARK: - Account screen (AccountScreen.kt + AccountSettingsScreen.kt parity)

struct AccountView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var showLogin = false
    @State private var showAdvanced = false
    @State private var advancedText = ""
    @State private var advancedError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Account", showBack: true) {
                    EmptyView()
                }
                if account.isLoggedIn {
                    signedInCard
                    accountActions
                } else {
                    signedOutCard
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .sheet(isPresented: $showLogin) {
            WebLoginSheet(title: "Sign in with Google",
                          startUrl: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com",
                          desktopUserAgent: false,
                          shouldCapture: { url, _ in
                              url.absoluteString.hasPrefix("https://music.youtube.com")
                          },
                          onCookies: { cookies in
                              handleLoginCookies(cookies)
                          })
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedLoginSheet(text: $advancedText) { parsed in
                account.applyAdvancedLogin(parsed)
                showAdvanced = false
            }
            .presentationDetents([.large])
        }
    }

    private var signedInCard: some View {
        VStack(spacing: 14) {
            SongThumb(url: account.accountPhoto, size: 84, corner: 42, circle: true)
            VStack(spacing: 4) {
                Text(account.accountName ?? "Signed in")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                if let email = account.accountEmail {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                }
                if let handle = account.accountHandle, !handle.isEmpty {
                    Text(handle)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var accountActions: some View {
        SettingsGroup(title: "") {
            Button {
                account.logOut()
            } label: {
                SettingsNavRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign out", subtitle: "Removes the YouTube session from this device")
            }
            .buttonStyle(.plain)
        }
    }

    private var signedOutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sign in to YouTube", systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.textPrimary)
            Text("Sign in with your Google account to sync your YouTube Music library: liked songs, playlists, albums, artists and subscriptions. Your watch history also keeps recording.")
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
            Button {
                showLogin = true
            } label: {
                Text("Continue with Google")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(pal.accent))
            }
            .buttonStyle(.plain)
            Button {
                showAdvanced = true
            } label: {
                Text("Advanced login")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pal.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func handleLoginCookies(_ cookies: [HTTPCookie]) {
        let relevant = cookies.filter { $0.domain.contains("youtube.com") || $0.domain.contains("google.com") }
        let cookieString = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard cookieString.contains("SAPISID") else { return }
        account.completeSignIn(cookie: cookieString, visitorData: nil, dataSyncId: nil)
    }
}

// MARK: - Advanced login sheet (Android's 6-line token editor)

struct AdvancedLoginSheet: View {
    @Binding var text: String
    var onApply: (AccountManager.AdvancedLogin) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste the token set exported from another device. The INNERTUBE COOKIE line must contain SAPISID.")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 240)
                        .scrollContentBackground(.hidden)
                        .background(RoundedRectangle(cornerRadius: 12).fill(pal.surfaceHigh))
                        .colorMultiply(pal.textPrimary)
                    if let error = error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(pal.background.ignoresSafeArea())
            .navigationTitle("Advanced login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign in") {
                        if let parsed = AccountManager.parseAdvancedLogin(text) {
                            onApply(parsed)
                        } else {
                            error = "Invalid token set — the cookie line must contain SAPISID."
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Library sync section (SyncUtils parity — shown in Library)

struct LibrarySyncSection: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var syncedPlaylists: [MediaGridItem] = []
    @State private var syncedAlbums: [MediaGridItem] = []
    @State private var syncedArtists: [MediaGridItem] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "From YouTube Music")
            if isLoading {
                HStack { Spacer(); ProgressView().padding(.vertical, 24); Spacer() }
            } else if syncedPlaylists.isEmpty && syncedAlbums.isEmpty && syncedArtists.isEmpty {
                EmptyPlaceholder(icon: "person.crop.circle", text: "Sign in to sync your saved playlists, albums and artists.")
            } else {
                if !syncedPlaylists.isEmpty {
                    ItemShelf(shelf: Shelf(title: "Playlists", subtitle: nil, items: syncedPlaylists)) { song, songs in
                        player.play(song, queue: songs, sourceName: "Playlists")
                    }
                }
                if !syncedAlbums.isEmpty {
                    ItemShelf(shelf: Shelf(title: "Albums", subtitle: nil, items: syncedAlbums)) { song, songs in
                        player.play(song, queue: songs, sourceName: "Albums")
                    }
                }
                if !syncedArtists.isEmpty {
                    ItemShelf(shelf: Shelf(title: "Artists", subtitle: nil, items: syncedArtists), circleItems: true) { song, songs in
                        player.play(song, queue: songs, sourceName: "Artists")
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard account.isLoggedIn, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let shelves = try? await InnerTube.shared.library(browseId: "FEmusic_liked_playlists") {
            let items = shelves.flatMap(\.items)
            let filtered = items.filter { item in
                if case .playlist(let p) = item {
                    return p.browseId != "VLLM" && p.browseId != "SE"
                }
                return false
            }
            syncedPlaylists = Array(filtered.prefix(12))
        }
        if let shelves = try? await InnerTube.shared.library(browseId: "FEmusic_liked_albums") {
            syncedAlbums = Array(shelves.flatMap(\.items).filter { item in
                if case .album = item { return true }
                return false
            }.prefix(12))
        }
        if let shelves = try? await InnerTube.shared.library(browseId: "FEmusic_library_corpus_artists") {
            syncedArtists = Array(shelves.flatMap(\.items).filter { item in
                if case .artist = item { return true }
                return false
            }.prefix(12))
        }
    }
}
