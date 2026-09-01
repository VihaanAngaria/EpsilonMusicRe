import SwiftUI

/// Settings — mirrors the Android settings structure (Appearance / Player /
/// About) using the subset of preferences that apply on iOS.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var showClearHistoryConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Settings", showBack: true) {
                    EmptyView()
                }

                settingsGroup("Appearance") {
                    Picker("Theme", selection: $settings.themeModeRaw) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    Toggle("Pure black theme", isOn: $settings.pureBlack)
                    Toggle("Dynamic theme (color from artwork)", isOn: $settings.dynamicTheme)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent color")
                            .font(.system(size: 13))
                            .foregroundStyle(pal.textSecondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                            ForEach(AppSettings.accentOptions) { option in
                                Button {
                                    settings.accentHex = option.hex
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(option.color)
                                            .frame(width: 34, height: 34)
                                        if settings.accentHex == option.hex {
                                            Circle()
                                                .strokeBorder(.white, lineWidth: 2.5)
                                                .frame(width: 34, height: 34)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                settingsGroup("Player") {
                    Toggle("Autoplay related songs", isOn: $settings.autoplayRelated)
                    Toggle("Skip unavailable tracks", isOn: $settings.skipOnStreamError)
                    Picker("Default search filter", selection: $settings.defaultSearchFilterRaw) {
                        ForEach(SearchFilter.allCases) { filter in
                            Text(filter.title).tag(filter.rawValue)
                        }
                    }
                }

                settingsGroup("Data") {
                    Button(role: .destructive) {
                        showClearHistoryConfirm = true
                    } label: {
                        Text("Clear play history")
                    }
                    Button(role: .destructive) {
                        player.stop()
                    } label: {
                        Text("Stop playback & clear queue")
                    }
                }

                settingsGroup("About") {
                    LabeledRow(label: "App", value: "Epsilon Music (iOS edition)")
                    LabeledRow(label: "Version", value: appVersion)
                    LabeledRow(label: "Music source", value: "YouTube Music (InnerTube)")
                    LabeledRow(label: "Lyrics source", value: "LRCLIB")
                    if let url = URL(string: "https://github.com/VihaanAngaria/EpsilonMusicRe") {
                        Link(destination: url) {
                            HStack {
                                Text("Source code")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    Text("The iOS edition mirrors the Android app's design and core experience: YouTube Music streaming, search, home feed, playlists, queue, radio, synced lyrics and dynamic theming. Account sign-in, downloads, equalizer and Listen-Together hosting remain Android-only for now.")
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.top, 6)
                }

                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .alert("Clear play history?", isPresented: $showClearHistoryConfirm) {
            Button("Clear", role: .destructive) { library.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your listening history and top-track statistics will be reset.")
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pal.textSecondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
            .padding(.horizontal, 16)
        }
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
