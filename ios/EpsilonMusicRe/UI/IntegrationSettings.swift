import SwiftUI
import WebKit

// MARK: - Discord settings (DiscordSettings.kt parity)

struct DiscordSettingsView: View {
    @EnvironmentObject private var discord: DiscordPresence
    @Environment(\.epsPalette) private var pal

    @State private var showLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Discord Rich Presence", showBack: true) { EmptyView() }

                SettingsGroup(title: "") {
                    SettingsToggleRow(icon: "person.2.wave.2.fill",
                                      title: "Enable Discord RPC",
                                      subtitle: "Show what you're listening to on your Discord profile",
                                      isOn: Binding(
                                        get: { discord.enabled },
                                        set: { discord.enabled = $0; if $0 { discord.connect() } else { discord.disconnect() } }))
                    SettingsDivider()
                    SettingsValueRow(icon: "waveform.path.ecg", title: "Status", value: discord.connectionState.isEmpty ? "Disconnected" : discord.connectionState)
                    SettingsDivider()
                    if let error = discord.lastError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .padding(16)
                        SettingsDivider()
                    }
                }

                if discord.token.isEmpty {
                    SettingsGroup(title: "Account") {
                        Button {
                            showLogin = true
                        } label: {
                            SettingsNavRow(icon: "person.badge.key", title: "Log in with Discord",
                                           subtitle: "Opens the Discord login page and captures your session token locally")
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    SettingsGroup(title: "Account") {
                        SettingsValueRow(icon: "person.crop.circle.fill", title: discord.showUsername.isEmpty ? "Signed in" : discord.showUsername, value: "")
                        SettingsDivider()
                        SettingsToggleRow(icon: "eye",
                                          title: "Show when paused",
                                          subtitle: "Keep the activity visible while paused",
                                          isOn: Binding(get: { discord.showWhenPaused }, set: { discord.showWhenPaused = $0 }))
                        SettingsDivider()
                        Button {
                            discord.token = ""
                            discord.disconnect()
                        } label: {
                            SettingsNavRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign out")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .sheet(isPresented: $showLogin) {
            DiscordLoginSheet()
                .presentationDetents([.large])
        }
    }
}

// MARK: Discord login (DiscordTokenWebView.kt parity — localStorage token capture)

struct DiscordLoginSheet: View {
    @EnvironmentObject private var discord: DiscordPresence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal

    @State private var token: String = ""
    @State private var showWebView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 36))
                    .foregroundStyle(pal.accent)
                Text("Discord login")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(pal.textPrimary)
                Text("Sign in on discord.com in the sheet below. Epsilon Music reads the session token from the page's local storage — it never leaves your device (the Discord gateway is contacted directly).")
                    .font(.system(size: 13))
                    .foregroundStyle(pal.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    showWebView = true
                } label: {
                    Text("Open Discord login")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(pal.accent))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                Spacer()
            }
            .padding(.top, 32)
            .background(pal.background.ignoresSafeArea())
            .navigationTitle("Discord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showWebView) {
                WebViewSheetWithTokenCapture(startUrl: "https://discord.com/login") { captured in
                    discord.token = captured
                    discord.connect()
                    dismiss()
                }
            }
        }
    }
}

/// WebView that reads the Discord token from localStorage after login.
struct WebViewSheetWithTokenCapture: View {
    let startUrl: String
    var onToken: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                TokenCaptureWebView(startUrl: startUrl, onToken: { token in
                    onToken(token)
                }, isLoading: $isLoading)
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(pal.background.opacity(0.5))
                }
            }
            .navigationTitle("discord.com")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct TokenCaptureWebView: UIViewRepresentable {
    let startUrl: String
    var onToken: (String) -> Void
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: startUrl) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: TokenCaptureWebView
        private var captured = false

        init(parent: TokenCaptureWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            guard !captured else { return }
            // Look for the token in localStorage once we land in the app.
            let url = webView.url?.absoluteString ?? ""
            guard url.contains("discord.com/channels") || url.contains("discord.com/app") || url.contains("discord.com/login") else { return }
            webView.evaluateJavaScript("window.localStorage.getItem('token')") { result, _ in
                if let token = result as? String, !token.isEmpty, token != "null" {
                    DispatchQueue.main.async {
                        self.captured = true
                        self.parent.onToken(token.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
    }
}

// MARK: - Scrobbling settings (LastFMSettingsScreen + ListenBrainzManager parity)

struct ScrobblingSettingsView: View {
    @EnvironmentObject private var scrobbler: Scrobbler
    @Environment(\.epsPalette) private var pal

    @State private var lbToken = ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiKey = ""
    @State private var secret = ""
    @State private var loginMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Scrobbling", showBack: true) { EmptyView() }

                // ListenBrainz
                SettingsGroup(title: "ListenBrainz") {
                    SettingsToggleRow(icon: "brain.head.profile",
                                      title: "Enable ListenBrainz",
                                      subtitle: "Submit playing-now and finished listens",
                                      isOn: Binding(get: { scrobbler.listenBrainzEnabled }, set: { scrobbler.listenBrainzEnabled = $0 }))
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User token")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(pal.textSecondary)
                        SecureField("Paste your token from listenbrainz.org/settings", text: $lbToken)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                        Button("Save token") {
                            scrobbler.listenBrainzToken = lbToken.trimmingCharacters(in: .whitespaces)
                            loginMessage = "ListenBrainz token saved."
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pal.accent)
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }

                // Last.fm
                SettingsGroup(title: "Last.fm") {
                    SettingsToggleRow(icon: "chart.line.uptrend.xyaxis",
                                      title: "Enable Last.fm",
                                      subtitle: "Scrobbles with a mobile-session login",
                                      isOn: Binding(get: { scrobbler.lastfmEnabled }, set: { scrobbler.lastfmEnabled = $0 }))
                    if scrobbler.lastfmEnabled {
                        SettingsDivider()
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Username", text: $username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            SecureField("Password", text: $password)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            TextField("API key", text: $apiKey)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            SecureField("Shared secret", text: $secret)
                                .font(.system(size: 13, design: .monospaced))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(pal.surfaceHigh))
                            HStack {
                                Button("Log in") {
                                    scrobbler.lastfmUsername = username
                                    scrobbler.lastfmPassword = password
                                    scrobbler.lastfmApiKey = apiKey
                                    scrobbler.lastfmSecret = secret
                                    Task {
                                        let ok = await scrobbler.lastfmLogin()
                                        loginMessage = ok ? "Last.fm session established." : (scrobbler.lastError ?? "Login failed")
                                    }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(pal.accent)
                                .buttonStyle(.plain)
                                if scrobbler.lastfmSession != nil {
                                    Text("Session active")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                            if scrobbler.lastfmSession == nil {
                                Text("Last.fm needs the API key and secret of a registered app. Create one at last.fm/api/account/create.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(pal.textSecondary)
                            }
                        }
                        .padding(16)
                        SettingsDivider()
                        SettingsToggleRow(icon: "dot.radiowaves.left.and.right",
                                          title: "Send now playing",
                                          isOn: Binding(get: { scrobbler.lastfmSendNowPlaying }, set: { scrobbler.lastfmSendNowPlaying = $0 }))
                        SettingsDivider()
                        SettingsToggleRow(icon: "heart",
                                          title: "Send likes",
                                          isOn: Binding(get: { scrobbler.lastfmSendLikes }, set: { scrobbler.lastfmSendLikes = $0 }))
                    }
                }

                SettingsGroup(title: "Scrobble threshold") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Submit after \(Int(scrobbler.scrobbleDelayPercent * 100))% of the song or 3 minutes, whichever comes first")
                                .font(.system(size: 13))
                                .foregroundStyle(pal.textSecondary)
                            Spacer()
                        }
                        Slider(value: Binding(
                            get: { scrobbler.scrobbleDelayPercent },
                            set: { scrobbler.scrobbleDelayPercent = $0 }), in: 0.1...1, step: 0.05)
                            .tint(pal.accent)
                    }
                    .padding(16)
                }

                if let message = loginMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(.horizontal, 16)
                }
                if let error = scrobbler.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .onAppear {
            lbToken = scrobbler.listenBrainzToken
            username = scrobbler.lastfmUsername
            password = scrobbler.lastfmPassword
            apiKey = scrobbler.lastfmApiKey
            secret = scrobbler.lastfmSecret
        }
    }
}

// MARK: - Listen Together settings

struct ListenTogetherSettingsView: View {
    @EnvironmentObject private var lt: ListenTogetherClient
    @Environment(\.epsPalette) private var pal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Listen Together", showBack: true) { EmptyView() }
                SettingsGroup(title: "Session") {
                    SettingsValueRow(icon: "server.rack", title: "Server", value: LTServers.selectedUrl)
                }
                SettingsGroup(title: "How it works") {
                    Text("Listen Together syncs playback across devices over a WebSocket relay: the host controls playback, guests buffer the same track and everyone starts together. Chats, track suggestions, host transfer and participant permissions match the Android edition.")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.textSecondary)
                        .padding(16)
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}
