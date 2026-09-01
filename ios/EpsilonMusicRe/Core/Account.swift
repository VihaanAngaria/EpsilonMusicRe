import Foundation
import CryptoKit
import Combine

/// YouTube account manager — the iOS counterpart of the Android app's login
/// flow (LoginScreen.kt / App.kt). Sign-in happens in a WKWebView that loads
/// accounts.google.com with a continue-URL of music.youtube.com; when the
/// WebView lands on music.youtube.com we harvest the cookie string, VISITOR_DATA
/// and DATASYNC_ID (via page JS), exactly like the Android WebView bridge.
final class AccountManager: ObservableObject {

    static let shared = AccountManager()

    // MARK: Published state

    @Published var accountName: String?
    @Published var accountEmail: String?
    @Published var accountHandle: String?
    @Published var accountPhoto: String?
    @Published var isSigningIn = false

    // MARK: Raw session material (persisted)

    /// The full cookie header string for music.youtube.com ("VISITOR_INFO1_LIVE=…; SAPISID=…").
    var cookie: String? {
        get { UserDefaults.standard.string(forKey: "yt_cookie") }
        set { UserDefaults.standard.set(newValue, forKey: "yt_cookie") }
    }
    var dataSyncId: String? {
        get { UserDefaults.standard.string(forKey: "yt_datasync_id") }
        set { UserDefaults.standard.set(newValue, forKey: "yt_datasync_id") }
    }
    var visitorData: String? {
        get { UserDefaults.standard.string(forKey: "yt_visitor_data") }
        set { UserDefaults.standard.set(newValue, forKey: "yt_visitor_data") }
    }

    var isLoggedIn: Bool {
        guard let cookie = cookie else { return false }
        return cookie.contains("SAPISID")
    }

    private init() {
        refreshFromPrefs()
        if isLoggedIn {
            Task { await validateAccount() }
        }
    }

    func refreshFromPrefs() {
        accountName = UserDefaults.standard.string(forKey: "yt_account_name")
        accountEmail = UserDefaults.standard.string(forKey: "yt_account_email")
        accountHandle = UserDefaults.standard.string(forKey: "yt_account_handle")
        accountPhoto = UserDefaults.standard.string(forKey: "yt_account_photo")
    }

    // MARK: SAPISIDHASH authorization (Android Utils.kt parity)

    /// `Authorization: SAPISIDHASH <epoch>_<sha1("<epoch> <SAPISID> https://music.youtube.com")>`
    static func sapisidHash(cookie: String, epoch: Int = Int(Date().timeIntervalSince1970)) -> String {
        guard let sapisid = cookie
            .components(separatedBy: ";")
            .compactMap({ $0.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).first.map(String.init) })
            .contains("SAPISID") else {
            // fall back: find SAPISID value the easy way
            return ""
        }
        var sapisidValue = ""
        for part in cookie.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SAPISID=") {
                sapisidValue = String(trimmed.dropFirst("SAPISID=".count))
            }
        }
        guard !sapisidValue.isEmpty else { return "" }
        let input = "\(epoch) \(sapisidValue) https://music.youtube.com"
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(epoch)_\(hex)"
    }

    /// Headers to attach to logged-in InnerTube requests.
    func authHeaders() -> [String: String]? {
        guard isLoggedIn, let cookie = cookie else { return nil }
        var headers = ["Cookie": cookie]
        let hash = Self.sapisidHash(cookie: cookie)
        if !hash.isEmpty {
            headers["Authorization"] = "SAPISIDHASH \(hash)"
        }
        return headers
    }

    /// `context.user.onBehalfOfUser` value (DataSyncId, "a||b" → "a").
    var onBehalfOfUser: String? {
        guard let id = dataSyncId, !id.isEmpty else { return nil }
        return id.components(separatedBy: "||").first
    }

    // MARK: Validation (account/account_menu)

    func validateAccount() async {
        guard isLoggedIn else { return }
        do {
            let json = try await InnerTube.shared.accountMenu()
            let header = JSON.dig(json, "actions", 0, "openPopupAction", "popup", "multiPageMenuRenderer", "header", "activeAccountHeaderRenderer")
            let name = InnerTube.runsText(JSON.dig(header, "accountName", "runs"))
            let email = InnerTube.runsText(JSON.dig(header, "email", "runs"))
            let handle = InnerTube.runsText(JSON.dig(header, "channelHandle", "runs"))
            let photos = JSON.asArray(JSON.dig(header, "accountPhoto", "thumbnails")) ?? []
            let photo = InnerTube.thumbnailUrl(photos)
            await MainActor.run {
                if let name = name {
                    accountName = name
                    UserDefaults.standard.set(name, forKey: "yt_account_name")
                }
                if let email = email {
                    accountEmail = email
                    UserDefaults.standard.set(email, forKey: "yt_account_email")
                }
                if let handle = handle {
                    accountHandle = handle
                    UserDefaults.standard.set(handle, forKey: "yt_account_handle")
                }
                if let photo = photo {
                    accountPhoto = photo
                    UserDefaults.standard.set(photo, forKey: "yt_account_photo")
                }
            }
        } catch {
            // Offline start — keep persisted profile.
        }
    }

    // MARK: Sign-in completion (called from the login WebView)

    func completeSignIn(cookie: String, visitorData: String?, dataSyncId: String?) {
        self.cookie = cookie
        if let v = visitorData, !v.isEmpty { self.visitorData = v }
        if let d = dataSyncId, !d.isEmpty { self.dataSyncId = d }
        isSigningIn = false
        objectWillChange.send()
        Task { await validateAccount() }
    }

    /// Advanced login data — the Android 6-line token format.
    struct AdvancedLogin {
        var cookie: String
        var visitorData: String?
        var dataSyncId: String?
        var name: String?
        var email: String?
        var handle: String?
    }

    /// Advanced login — the Android 6-line token format (SAPISID required).
    static func parseAdvancedLogin(_ text: String) -> AdvancedLogin? {
        var cookie: String?
        var visitorData: String?
        var dataSyncId: String?
        var name: String?
        var email: String?
        var handle: String?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("***INNERTUBE COOKIE***") {
                cookie = trimmed.dropFirst("***INNERTUBE COOKIE***".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("***VISITOR DATA***") {
                visitorData = trimmed.dropFirst("***VISITOR DATA***".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("***DATASYNC ID***") {
                dataSyncId = trimmed.dropFirst("***DATASYNC ID***".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("***ACCOUNT NAME***") {
                name = trimmed.dropFirst("***ACCOUNT NAME***".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("***ACCOUNT EMAIL***") {
                email = trimmed.dropFirst("***ACCOUNT EMAIL***".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("***ACCOUNT CHANNEL HANDLE***") {
                handle = trimmed.dropFirst("***ACCOUNT CHANNEL HANDLE***".count).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let c = cookie, c.contains("SAPISID") else { return nil }
        return AdvancedLogin(cookie: c, visitorData: visitorData, dataSyncId: dataSyncId, name: name, email: email, handle: handle)
    }

    func applyAdvancedLogin(_ parsed: AdvancedLogin) {
        cookie = parsed.cookie
        visitorData = parsed.visitorData
        dataSyncId = parsed.dataSyncId
        UserDefaults.standard.set(parsed.name, forKey: "yt_account_name")
        UserDefaults.standard.set(parsed.email, forKey: "yt_account_email")
        UserDefaults.standard.set(parsed.handle, forKey: "yt_account_handle")
        refreshFromPrefs()
        Task { await validateAccount() }
    }

    // MARK: Logout

    func logOut() {
        let keys = ["yt_cookie", "yt_datasync_id", "yt_visitor_data", "yt_account_name", "yt_account_email", "yt_account_handle", "yt_account_photo"]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        accountName = nil
        accountEmail = nil
        accountHandle = nil
        accountPhoto = nil
    }
}
