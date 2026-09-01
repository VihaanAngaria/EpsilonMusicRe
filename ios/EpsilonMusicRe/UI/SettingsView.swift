import SwiftUI

/// Settings — the Android SettingsScreen parity: searchable list with
/// Account, Appearance, Player and audio, Listen Together, Content,
/// AI lyrics translation, Privacy, Storage, Backup & restore, System
/// update, and About.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var updater: Updater
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Settings", showBack: true) { EmptyView() }

                // Search field (SettingsScreen search).
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(pal.textSecondary)
                    TextField("Search settings", text: $searchQuery)
                        .font(.system(size: 15))
                        .foregroundStyle(pal.textPrimary)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(pal.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 24).fill(pal.surface))
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Account card.
                if matches("account", "sign in", "google", "youtube") {
                    NavigationLink {
                        AccountView()
                    } label: {
                        accountCard
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroup(title: "") {
                    if matches("appearance", "theme", "dark", "accent", "color", "black") {
                        NavigationLink {
                            AppearanceSettingsView()
                        } label: {
                            SettingsNavRow(icon: "paintpalette.fill", title: "Appearance",
                                           subtitle: "Theme, pure black, dynamic colors, accents, player look")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("player", "audio", "equalizer", "crossfade", "normalization", "silence", "queue", "lyrics") {
                        NavigationLink {
                            PlayerSettingsView()
                        } label: {
                            SettingsNavRow(icon: "waveform", title: "Player and audio",
                                           subtitle: "Equalizer, crossfade, normalization, skip silence, queue")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("listen together", "sync", "room") {
                        NavigationLink {
                            ListenTogetherSettingsView()
                        } label: {
                            SettingsNavRow(icon: "person.2.wave.2.fill", title: "Listen Together",
                                           subtitle: "Sessions, servers and sync behavior")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("content", "history", "search", "local") {
                        NavigationLink {
                            ContentSettingsView()
                        } label: {
                            SettingsNavRow(icon: "square.grid.2x2.fill", title: "Content",
                                           subtitle: "On-device music, history and search preferences")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("ai", "lyrics", "translation", "translation", "deepl", "openrouter") {
                        NavigationLink {
                            AISettingsView()
                        } label: {
                            SettingsNavRow(icon: "wand.and.stars", title: "AI lyrics translation",
                                           subtitle: "Provider, keys, language and auto-translate")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("discord", "presence", "rpc") {
                        NavigationLink {
                            DiscordSettingsView()
                        } label: {
                            SettingsNavRow(icon: "person.2.wave.2", title: "Discord Rich Presence",
                                           subtitle: "Show your music on Discord")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("scrobble", "last.fm", "lastfm", "listenbrainz") {
                        NavigationLink {
                            ScrobblingSettingsView()
                        } label: {
                            SettingsNavRow(icon: "chart.line.uptrend.xyaxis", title: "Scrobbling",
                                           subtitle: "ListenBrainz and Last.fm")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("recognition", "shazam", "identify", "music recognition") {
                        NavigationLink {
                            RecognitionView()
                        } label: {
                            SettingsNavRow(icon: "waveform.badge.magnifyingglass", title: "Music recognition",
                                           subtitle: "Identify songs with the microphone")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("privacy", "telemetry", "data") {
                        NavigationLink {
                            PrivacySettingsView()
                        } label: {
                            SettingsNavRow(icon: "lock.shield.fill", title: "Privacy", subtitle: "What stays on your device")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("storage", "download", "cache", "offline") {
                        NavigationLink {
                            StorageSettingsView()
                        } label: {
                            SettingsNavRow(icon: "internaldrive.fill", title: "Storage",
                                           subtitle: "Downloads, song and image caches")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("backup", "restore", "export", "import", "spotify", "csv") {
                        NavigationLink {
                            BackupRestoreView()
                        } label: {
                            SettingsNavRow(icon: "externaldrive.badge.timemachine", title: "Backup and restore",
                                           subtitle: "Export/import settings and library, playlist import")
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("update", "version", "release") {
                        NavigationLink {
                            UpdateSettingsView()
                        } label: {
                            SettingsNavRow(icon: "arrow.down.circle.fill", title: "System update",
                                           subtitle: updater.updateInfo == nil
                                                ? "Up to date (\(updater.currentVersion))"
                                                : "Version \(updater.updateInfo!.version) available",
                                           isHighlight: updater.updateInfo != nil)
                        }
                        .buttonStyle(.plain)
                        SettingsDivider()
                    }
                    if matches("about", "version", "credits", "github") {
                        NavigationLink {
                            AboutView()
                        } label: {
                            SettingsNavRow(icon: "info.circle.fill", title: "About", subtitle: "Version and credits")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task {
            if updater.autoCheck && updater.updateInfo == nil && !updater.isChecking {
                await updater.checkForUpdates()
            }
        }
    }

    private func matches(_ keywords: String...) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        let titles = [keywords, ["settings"]].flatMap { $0 }
        return keywords.contains { $0.contains(query) } || titles.contains { $0.contains(query) }
    }

    private var accountCard: some View {
        HStack(spacing: 14) {
            if account.isLoggedIn {
                SongThumb(url: account.accountPhoto, size: 48, corner: 24, circle: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.accountName ?? "Signed in")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                    Text(account.accountEmail ?? "Manage your YouTube account")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(pal.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Account")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pal.textPrimary)
                    Text("Sign in to sync your library")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pal.textSecondary.opacity(0.6))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.surface))
        .padding(.horizontal, 12)
        .padding(.top, 16)
    }
}

extension SettingsNavRow {
    init(icon: String, title: String, subtitle: String?, isHighlight: Bool) {
        self.init(icon: icon, title: title, subtitle: subtitle)
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(pal.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(pal.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 14))
        .padding(.vertical, 6)
    }
}
