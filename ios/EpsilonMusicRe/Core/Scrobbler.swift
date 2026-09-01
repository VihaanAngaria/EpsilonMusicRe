import Foundation
import CryptoKit

/// Scrobbling — the Swift port of ListenBrainzManager.kt and the Last.fm
/// client (utils/lastfm). Triggers mirror ScrobbleManager: "playing now" on
/// track start, a completed listen when the play threshold (min(50% of
/// duration, 180 s), songs ≥ 30 s) is crossed.
@MainActor
final class Scrobbler: ObservableObject {

    static let shared = Scrobbler()

    // ListenBrainz
    var listenBrainzEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "listenbrainz_enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "listenbrainz_enabled") }
    }
    var listenBrainzToken: String {
        get { UserDefaults.standard.string(forKey: "listenbrainz_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "listenbrainz_token") }
    }

    // Last.fm
    var lastfmEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "lastfmScrobblingEnable") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmScrobblingEnable") }
    }
    var lastfmUsername: String {
        get { UserDefaults.standard.string(forKey: "lastfmUsername") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmUsername") }
    }
    var lastfmPassword: String {
        get { UserDefaults.standard.string(forKey: "lastfmPassword") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmPassword") }
    }
    var lastfmApiKey: String {
        get { UserDefaults.standard.string(forKey: "lastfmApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmApiKey") }
    }
    var lastfmSecret: String {
        get { UserDefaults.standard.string(forKey: "lastfmSecret") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmSecret") }
    }
    var lastfmSession: String? {
        get { UserDefaults.standard.string(forKey: "lastfmSession") }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmSession") }
    }
    var lastfmSendNowPlaying: Bool {
        get { UserDefaults.standard.object(forKey: "lastfmUseNowPlaying") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmUseNowPlaying") }
    }
    var lastfmSendLikes: Bool {
        get { UserDefaults.standard.object(forKey: "lastfmUseSendLikes") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "lastfmUseSendLikes") }
    }
    var scrobbleDelayPercent: Double {
        get { UserDefaults.standard.object(forKey: "scrobbleDelayPercent") as? Double ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: "scrobbleDelayPercent") }
    }
    var scrobbleMinDuration: Int {
        get { UserDefaults.standard.object(forKey: "scrobbleMinSongDuration") as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: "scrobbleMinSongDuration") }
    }

    @Published var lastError: String?

    private var playedSeconds: Double = 0
    private var scrobbledTrackId: String?
    private var nowPlayingTrackId: String?

    private init() {}

    // MARK: Playback hooks (called by PlayerManager)

    func trackStarted(song: Song, duration: Int) {
        playedSeconds = 0
        scrobbledTrackId = nil
        nowPlayingTrackId = song.id
        submitNowPlaying(song: song, duration: duration)
    }

    func tick(seconds: Double, song: Song, duration: Int) {
        guard song.id != scrobbledTrackId else { return }
        playedSeconds += seconds
        let threshold = min(Double(duration) * scrobbleDelayPercent, 180)
        if duration >= scrobbleMinDuration, playedSeconds >= threshold {
            scrobbledTrackId = song.id
            submitScrobble(song: song, duration: duration)
        }
    }

    // MARK: ListenBrainz

    private func submitNowPlaying(song: Song, duration: Int) {
        if listenBrainzEnabled, !listenBrainzToken.isEmpty {
            let payload: [String: Any] = [
                "listen_type": "playing_now",
                "payload": [[
                    "track_metadata": metadata(for: song, duration: duration, position: nil, playingNow: true)
                ]]
            ]
            post(listenBrainz: payload)
        }
        if lastfmEnabled, lastfmSession != nil, lastfmSendNowPlaying {
            lastfmUpdateNowPlaying(song: song, duration: duration)
        }
    }

    private func submitScrobble(song: Song, duration: Int) {
        if listenBrainzEnabled, !listenBrainzToken.isEmpty {
            let payload: [String: Any] = [
                "listen_type": "single",
                "payload": [[
                    "listened_at": max(Int(Date().timeIntervalSince1970), 1_033_430_400),
                    "track_metadata": metadata(for: song, duration: duration, position: nil, playingNow: false)
                ]]
            ]
            post(listenBrainz: payload)
        }
        if lastfmEnabled, lastfmSession != nil {
            lastfmScrobble(song: song, duration: duration)
        }
    }

    private func metadata(for song: Song, duration: Int, position: Double?, playingNow: Bool) -> [String: Any] {
        var meta: [String: Any] = [
            "artist_name": song.artistsText,
            "track_name": song.title,
            "submission_client": "Epsilon Music",
            "submission_client_version": "1.0.0",
        ]
        if let album = song.album, !album.isEmpty { meta["release_name"] = album }
        var info: [String: Any] = ["duration_ms": duration * 1000]
        if let position = position { info["position_ms"] = Int(position * 1000) }
        meta["additional_info"] = info
        return meta
    }

    private func post(listenBrainz payload: [String: Any]) {
        guard let request = LyricsHTTP.buildRequest(url: "https://api.listenbrainz.org/1/submit-listens",
                                                     method: "POST",
                                                     headers: [
                                                        "Authorization": "Token \(listenBrainzToken)",
                                                        "Content-Type": "application/json",
                                                     ],
                                                     body: try? JSONSerialization.data(withJSONObject: payload), timeout: 20) else { return }
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Task { @MainActor in
                    self?.lastError = "ListenBrainz error HTTP \(http.statusCode)"
                }
            }
        }.resume()
    }

    // MARK: Last.fm

    /// auth.getMobileSession — MD5-signed (same scheme as the Android client).
    func lastfmLogin() async -> Bool {
        guard !lastfmUsername.isEmpty, !lastfmPassword.isEmpty, !lastfmApiKey.isEmpty, !lastfmSecret.isEmpty else {
            lastError = "Last.fm needs a username, password, API key and secret"
            return false
        }
        var params: [String: String] = [
            "method": "auth.getMobileSession",
            "username": lastfmUsername,
            "password": lastfmPassword,
            "api_key": lastfmApiKey,
        ]
        params["api_sig"] = Self.md5Signature(params, secret: lastfmSecret)
        params["format"] = "json"
        guard let body = Self.formBody(params),
              let request = LyricsHTTP.buildRequest(url: "https://ws.audioscrobbler.com/2.0/",
                                                    method: "POST",
                                                    headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                                    body: body, timeout: 20) else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = JSON.parse(data) else {
                lastError = "Last.fm login failed"
                return false
            }
            if let key = JSON.asString(JSON.dig(json, "session", "key")) {
                lastfmSession = key
                lastError = nil
                return true
            }
            lastError = JSON.asString(JSON.dig(json, "message")) ?? "Last.fm login failed"
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func lastfmCall(_ method: String, extra: [String: String], signed: Bool) {
        guard let session = lastfmSession else { return }
        var params = extra
        params["method"] = method
        params["sk"] = session
        params["api_key"] = lastfmApiKey
        if signed {
            params["api_sig"] = Self.md5Signature(params, secret: lastfmSecret)
        }
        params["format"] = "json"
        guard let body = Self.formBody(params),
              let request = LyricsHTTP.buildRequest(url: "https://ws.audioscrobbler.com/2.0/",
                                                    method: "POST",
                                                    headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                                    body: body, timeout: 20) else { return }
        URLSession.shared.dataTask(with: request).resume()
    }

    private func lastfmUpdateNowPlaying(song: Song, duration: Int) {
        lastfmCall("track.updateNowPlaying", [
            "artist": song.artistsText,
            "track": song.title,
            "duration": "\(duration)",
        ], signed: true)
    }

    private func lastfmScrobble(song: Song, duration: Int) {
        lastfmCall("track.scrobble", [
            "artist": song.artistsText,
            "track": song.title,
            "duration": "\(duration)",
            "timestamp": "\(Int(Date().timeIntervalSince1970))",
        ], signed: true)
    }

    func lastfmLove(song: Song, love: Bool) {
        guard lastfmEnabled, lastfmSendLikes, lastfmSession != nil else { return }
        lastfmCall(love ? "track.love" : "track.unlove", [
            "artist": song.artistsText,
            "track": song.title,
        ], signed: true)
    }

    // MARK: Helpers

    static func md5Signature(_ params: [String: String], secret: String) -> String {
        let concatenated = params
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }
            .joined() + secret
        let digest = Insecure.MD5.hash(data: Data(concatenated.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func formBody(_ params: [String: String]) -> Data? {
        let pairs = params.map { key, value in
            "\(urlEscaped(key))=\(urlEscaped(value))"
        }
        return pairs.joined(separator: "&").data(using: .utf8)
    }
}
