import SwiftUI
import WebKit

// MARK: - Settings rows (Material3SettingsItem parity)

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pal.accent)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.surface))
                .padding(.horizontal, 12)
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(pal.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(pal.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(pal.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsNavRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(pal.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(pal.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(pal.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pal.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct SettingsValueRow: View {
    let icon: String
    let title: String
    var value: String

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(pal.accent)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(pal.textPrimary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(pal.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsDivider: View {
    @Environment(\.epsPalette) private var pal
    var body: some View {
        Rectangle()
            .fill(pal.surfaceHigh)
            .frame(height: 1)
            .padding(.leading, 58)
    }
}

// MARK: - Segmented chips (Simple | Advanced etc.)

/// Binding-based chips wrapper over the shared ChipsRow.
struct SelectionChips<T: Hashable & Identifiable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        ChipsRow(options: options, isSelected: { $0 == selection }) {
            selection = $0
        }
    }
}

struct SegmentedChips: View {
    let options: [String]
    @Binding var selection: Int

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = index
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == index ? .white : pal.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selection == index ? pal.accent : pal.surfaceHigh)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Safari-style in-app WebView sheet

/// A generic WebView sheet used by account login (Google), Discord token
/// capture and Spotify sp_dc capture — mirroring the Android WebView bridges.
struct WebLoginSheet: View {
    let title: String
    let startUrl: String
    let desktopUserAgent: Bool
    /// Returns true (and closes) when the page satisfies the login condition.
    var shouldCapture: (URL, WKWebView) -> Bool
    var onCookies: ([HTTPCookie]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                WebViewContainer(startUrl: startUrl,
                                 desktopUserAgent: desktopUserAgent,
                                 shouldCapture: shouldCapture,
                                 onCookies: { cookies in
                                     onCookies(cookies)
                                     dismiss()
                                 },
                                 isLoading: $isLoading)
                    .ignoresSafeArea(edges: .bottom)
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(pal.background.opacity(0.6))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let startUrl: String
    let desktopUserAgent: Bool
    var shouldCapture: (URL, WKWebView) -> Bool
    var onCookies: ([HTTPCookie]) -> Void
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        if desktopUserAgent {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        }
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
        let parent: WebViewContainer
        private var captured = false

        init(parent: WebViewContainer) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            guard !captured else { return }
            let url = webView.url ?? URL(string: parent.startUrl)!
            if parent.shouldCapture(url, webView) {
                captured = true
                let store = webView.configuration.websiteDataStore
                store.httpCookieStore.getAllCookies { cookies in
                    DispatchQueue.main.async {
                        self.parent.onCookies(cookies)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}

// MARK: - Download status button (player download pill parity)

struct DownloadButton: View {
    let song: Song
    var compact: Bool = false

    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    var body: some View {
        let isDownloaded = downloads.isDownloaded(song)
        let isDownloading = isPending
        Button {
            if isDownloaded {
                downloads.remove(song)
            } else if !isDownloading {
                downloads.download(song)
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: compact ? 14 : 17, weight: .medium))
                .foregroundStyle(isDownloaded ? pal.accent : (isDownloading ? pal.textSecondary : pal.textSecondary))
        }
        .buttonStyle(.plain)
    }

    private var isPending: Bool {
        if case .some(.downloading) = downloads.states[song.id] { return true }
        if case .some(.queued) = downloads.states[song.id] { return true }
        return false
    }

    private var iconName: String {
        if downloads.isDownloaded(song) { return "arrow.down.circle.fill" }
        if isPending { return "arrow.down.circle.badge.automatic" }
        if case .some(.failed) = downloads.states[song.id] { return "exclamationmark.circle" }
        return "arrow.down.circle"
    }
}

// MARK: - Stat card (ActivityHistory parity)

struct StatCard: View {
    let value: String
    let label: String

    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(pal.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(pal.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.surface))
    }
}

// MARK: - Period chips (StatsScreen parity)

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "1 week"
    case month = "1 month"
    case threeMonths = "3 months"
    case sixMonths = "6 months"
    case year = "1 year"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .all: return nil
        }
    }
}

func formatListenTime(_ seconds: Double) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(total)s"
}

// MARK: - Navigable media card (grid cards with route navigation)

struct NavigableMediaCard: View {
    let item: MediaGridItem
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        switch item {
        case .song(let song):
            MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
                .contentShape(Rectangle())
                .onTapGesture {
                    player.play(song, queue: [song], sourceName: "Charts")
                }
        case .artist(let artist):
            NavigationLink(value: Route.artist(artist)) {
                MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
            }
            .buttonStyle(.plain)
        case .album(let album):
            NavigationLink(value: Route.album(album)) {
                MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
            }
            .buttonStyle(.plain)
        case .playlist(let playlist):
            NavigationLink(value: Route.onlinePlaylist(playlist)) {
                MediaCard(title: item.title, subtitle: item.subtitle, thumbnail: item.thumbnail)
            }
            .buttonStyle(.plain)
        }
    }
}
