import Foundation

/// Discord Rich Presence over the user-account Gateway WebSocket — the Swift
/// port of the Android app's GatewayClient + DiscordSocialPresenceClient.
/// OP codes: HELLO(10) → heartbeat(1) + IDENTIFY(2) → READY → presence OP 3.
@MainActor
final class DiscordPresence: ObservableObject {

    static let shared = DiscordPresence()

    static let applicationId = "1543663936849584239"
    static let apiBase = "https://discord.com/api"

    // MARK: Settings (DiscordSettings.kt parity)

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enable_discord_rpc") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enable_discord_rpc") }
    }
    var token: String {
        get { UserDefaults.standard.string(forKey: "discord_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "discord_token") }
    }
    var showWhenPaused: Bool {
        get { UserDefaults.standard.object(forKey: "discord_show_when_paused") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "discord_show_when_paused") }
    }
    var showUsername: String {
        get { UserDefaults.standard.string(forKey: "discord_name") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "discord_name") }
    }

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var connectionState: String = ""

    private var socket: URLSessionWebSocketTask?
    private var heartbeatTimer: Timer?
    private var lastSequence: Int?
    private var reconnectAttempts = 0
    private var currentActivitySong: Song?

    private init() {
        if enabled && !token.isEmpty {
            connect()
        }
    }

    // MARK: Connection

    func connect() {
        guard enabled, !token.isEmpty else { return }
        disconnect()
        connectionState = "Connecting…"
        let url = URL(string: "wss://gateway.discord.gg/?v=9&encoding=json")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        receive()
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        lastSequence = nil
        isConnected = false
        connectionState = ""
    }

    private func receive() {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .failure:
                    self.scheduleReconnect()
                case .success(let message):
                    self.handle(message: message)
                    if self.socket != nil {
                        self.receive()
                    }
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard socket != nil else { return } // explicit disconnect
        isConnected = false
        connectionState = "Reconnecting…"
        reconnectAttempts += 1
        guard reconnectAttempts < 8 else {
            connectionState = ""
            return
        }
        let delay = Double(reconnectAttempts) * 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + min(delay, 30)) { [weak self] in
            Task { @MainActor in
                self?.connect()
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message, let data = text.data(using: .utf8),
              let json = JSON.parse(data),
              let op = JSON.asInt(json["op"]) else { return }
        if let seq = JSON.asInt(json["s"]) { lastSequence = seq }

        switch op {
        case 10: // HELLO
            let interval = JSON.asDouble(JSON.dig(json, "d", "heartbeat_interval")) ?? 30000
            startHeartbeat(intervalMs: interval)
            sendIdentify()
        case 11: // HEARTBEAT_ACK
            break
        case 0: // DISPATCH
            let type = JSON.asString(json["t"]) ?? ""
            if type == "READY" {
                isConnected = true
                reconnectAttempts = 0
                connectionState = "Connected"
                if let user = JSON.asString(JSON.dig(json, "d", "user", "username")) {
                    showUsername = user
                }
                if let song = currentActivitySong {
                    updatePresence(song: song)
                }
            }
        case 7: // RECONNECT
            scheduleReconnect()
        case 9: // INVALID_SESSION
            connectionState = ""
            lastError = "Discord rejected the session token"
        default:
            break
        }
    }

    private func startHeartbeat(intervalMs: Double) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: intervalMs / 1000.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
        sendHeartbeat()
    }

    private func sendHeartbeat() {
        var payload: [String: Any] = ["op": 1]
        if let seq = lastSequence { payload["d"] = seq } else { payload["d"] = NSNull() }
        send(json: payload)
    }

    private func sendIdentify() {
        let capabilities = (1 << 4) | (1 << 5) | (1 << 12) | (1 << 16)
        let intents = (1 << 12) | (1 << 18) | (1 << 19) | (1 << 22) | (1 << 23) | (1 << 27) | (1 << 28) | (1 << 29)
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "capabilities": capabilities,
                "intents": intents,
                "token": token,
                "properties": [
                    "os": "iOS",
                    "browser": "Epsilon Music",
                    "device": "iOS",
                    "browser_user_agent": "Epsilon Music",
                    "browser_version": "1.0",
                    "client_version": "1.0",
                    "client_build_number": 1,
                    "native_build_number": 1,
                    "release_channel": "unknown",
                ] as [String: Any],
            ] as [String: Any],
        ]
        send(json: payload)
    }

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { [weak self] error in
            if error != nil {
                Task { @MainActor in
                    self?.scheduleReconnect()
                }
            }
        }
    }

    // MARK: Presence updates (called by PlayerManager)

    func updatePresence(song: Song, position: Double = 0, isPlaying: Bool = true, duration: Int = 0) {
        currentActivitySong = song
        guard enabled, isConnected else { return }
        let activity = buildActivity(song: song, position: position, isPlaying: isPlaying, duration: duration)
        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "activities": activity.isEmpty ? [] : [activity],
                "afk": false,
                "since": NSNull(),
                "status": "online",
            ] as [String: Any],
        ]
        send(json: payload)
    }

    func clearPresence() {
        currentActivitySong = nil
        guard enabled, isConnected else { return }
        let payload: [String: Any] = [
            "op": 3,
            "d": [
                "activities": [],
                "afk": false,
                "since": NSNull(),
                "status": "online",
            ] as [String: Any],
        ]
        send(json: payload)
    }

    private func buildActivity(song: Song, position: Double, isPlaying: Bool, duration: Int) -> [String: Any] {
        if !isPlaying && !showWhenPaused {
            return [:]
        }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let start = now - Int(position * 1000)
        var timestamps: [String: Any] = ["start": start]
        if isPlaying, duration > 0 {
            timestamps["end"] = start + duration * 1000
        }
        var activity: [String: Any] = [
            "name": "Epsilon Music",
            "type": 2, // Listening
            "details": String(song.title.prefix(128)),
            "state": String(song.artistsText.prefix(128)),
            "application_id": Self.applicationId,
            "timestamps": timestamps,
            "buttons": ["Listen on YouTube Music", "Go to Epsilon Music"],
            "metadata": [
                "button_urls": [
                    "https://music.youtube.com/watch?v=\(song.videoId)",
                    "https://github.com/VihaanAngaria/EpsilonMusicRe",
                ],
            ] as [String: Any],
            "platform": "ios",
        ]
        if let thumb = song.thumbnailUrl, let url = URL(string: thumb), url.scheme == "https" {
            activity["assets"] = [
                "large_image": thumb,
                "large_text": song.album ?? song.title,
            ] as [String: Any]
        }
        return activity
    }

    // MARK: External assets (DiscordAssetRegistrar parity)

    /// Registers an external image URL and returns the "mp:" asset key.
    nonisolated static func registerExternalAsset(url: String, token: String) async -> String? {
        // media.discordapp.net URLs pass through with the mp: prefix directly.
        if url.contains("media.discordapp.net") {
            return "mp:" + url
        }
        let body = ["urls": [url]]
        guard let request = LyricsHTTP.buildRequest(url: "\(apiBase)/v10/applications/\(applicationId)/external-assets",
                                                    method: "POST",
                                                    headers: [
                                                        "Authorization": "Bearer \(token)",
                                                        "Content-Type": "application/json",
                                                    ],
                                                    body: try? JSONSerialization.data(withJSONObject: body), timeout: 15) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = JSON.parse(data),
              let assets = JSON.asArray(json) else { return nil }
        for asset in assets {
            if let path = JSON.asString(asset["external_asset_path"]) {
                return "mp:" + path
            }
        }
        return nil
    }
}
