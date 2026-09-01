import Foundation

// MARK: - Models (Protocol.kt parity)

struct LTTrackInfo: Codable, Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    var duration: Int
    var thumbnail: String?
    var suggestedBy: String?
}

struct LTUser: Codable, Equatable, Identifiable {
    var userId: String
    var username: String
    var isHost: Bool
    var isConnected: Bool

    var id: String { userId }
}

struct LTRoomState: Codable, Equatable {
    var roomCode: String
    var hostId: String
    var users: [LTUser]
    var currentTrack: LTTrackInfo?
    var isPlaying: Bool
    var position: Double
    var lastUpdate: Double
    var queue: [LTTrackInfo]
    var volume: Double
    var allowParticipantControl: Bool
}

struct LTChatMessage: Identifiable, Equatable {
    var id = UUID()
    var username: String
    var message: String
    var isHost: Bool
    var isSystem: Bool
    var timestamp: Double

    init(username: String, message: String, isHost: Bool = false, isSystem: Bool = false) {
        self.username = username
        self.message = message
        self.isHost = isHost
        self.isSystem = isSystem
        self.timestamp = Date().timeIntervalSince1970
    }
}

struct LTSuggestion: Identifiable, Equatable {
    var id = UUID()
    var suggestionId: String
    var track: LTTrackInfo
    var suggestedBy: String
}

// MARK: - Servers

enum LTServers {
    static let fallbacks = [
        "wss://metroserverx.meowery.eu/ws",
        "wss://devilmi-vivi-music-listen-together.hf.space",
    ]

    static var selectedUrl: String {
        get { UserDefaults.standard.string(forKey: "ListenTogetherServerUrl") ?? fallbacks[0] }
        set { UserDefaults.standard.set(newValue, forKey: "ListenTogetherServerUrl") }
    }

    struct ServerEntry: Codable, Identifiable {
        var name: String
        var region: String
        var serverUrl: String
        var id: String { serverUrl }
    }

    /// Fetches the public server list (app/server.json in the main repo).
    static func fetchServers() async -> [ServerEntry] {
        let url = "https://raw.githubusercontent.com/VihaanAngaria/EpsilonMusic/refs/heads/main/app/server.json"
        guard let (_, parsed) = await LyricsHTTP.get(url: url, timeout: 10),
              let json = parsed as? [String: Any],
              let name = JSON.asString(json["name"]),
              let serverUrl = JSON.asString(json["serverUrl"]) else {
            return fallbacks.map { ServerEntry(name: "Community server", region: "", serverUrl: $0) }
        }
        let region = JSON.asString(json["region"]) ?? ""
        return [ServerEntry(name: name, region: region, serverUrl: serverUrl)]
            + fallbacks.filter { $0 != serverUrl }.map { ServerEntry(name: "Fallback", region: "", serverUrl: $0) }
    }
}

// MARK: - Client (ListenTogetherManager + Client parity: JSON envelope over WS)

@MainActor
final class ListenTogetherClient: ObservableObject {

    static let shared = ListenTogetherClient()

    enum Phase: Equatable {
        case idle
        case connecting
        case awaitingApproval(roomCode: String)
        case inRoom(roomCode: String)
        case error(String)
    }

    enum PlayAction: String {
        case play, pause, seek, skipNext = "skip_next", skipPrev = "skip_prev"
        case changeTrack = "change_track", queueAdd = "queue_add", queueRemove = "queue_remove"
        case queueClear = "queue_clear", syncQueue = "sync_queue", setVolume = "set_volume"
    }

    @Published var phase: Phase = .idle
    @Published var roomState: LTRoomState?
    @Published var chat: [LTChatMessage] = []
    @Published var suggestions: [LTSuggestion] = []
    @Published var isHost = false
    @Published var serverClockOffset: Double = 0

    var username: String {
        get { UserDefaults.standard.string(forKey: "lt_username") ?? "iOS listener" }
        set { UserDefaults.standard.set(newValue, forKey: "lt_username") }
    }

    private var socket: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var sessionToken: String?
    private var userId: String?
    private var lastPongAt: Date?

    private init() {}

    // MARK: Connection

    func createRoom() {
        connect {
            self.send(type: "create_room", payload: ["username": self.username])
        }
    }

    func joinRoom(code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        connect {
            self.send(type: "join_room", payload: [
                "room_code": normalized,
                "username": self.username,
            ])
        }
    }

    private func connect(onOpen: @escaping () -> Void) {
        disconnect()
        phase = .connecting
        let url = URL(string: LTServers.selectedUrl)!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        // Allow the socket to settle, then identify.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onOpen()
            self.receiveLoop()
        }
        startPing()
    }

    func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        pingTimer?.invalidate()
        pingTimer = nil
        phase = .idle
        roomState = nil
        chat = []
        suggestions = []
        isHost = false
        sessionToken = nil
        userId = nil
    }

    func leave() {
        send(type: "leave_room", payload: [:])
        disconnect()
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.send(type: "ping", payload: [:])
            }
        }
    }

    private func receiveLoop() {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    if self.phase != .idle {
                        self.phase = .error(error.localizedDescription)
                    }
                case .success(let message):
                    self.handle(message: message)
                    if self.socket != nil {
                        self.receiveLoop()
                    }
                }
            }
        }
    }

    // MARK: Message handling

    private func handle(message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message, let data = text.data(using: .utf8),
              let parsed = JSON.parse(data), let json = parsed as? [String: Any] else { return }
        let type = JSON.asString(json["type"]) ?? ""
        let payload: [String: Any] = (json["payload"] as? [String: Any])
            ?? (json["d"] as? [String: Any]) ?? [:]

        switch type {
        case "room_created":
            let code = JSON.asString(payload["room_code"]) ?? ""
            userId = JSON.asString(payload["user_id"])
            sessionToken = JSON.asString(payload["session_token"])
            isHost = true
            phase = .inRoom(roomCode: code)
            roomState = LTRoomState(roomCode: code, hostId: userId ?? "", users: [LTUser(userId: userId ?? "", username: username, isHost: true, isConnected: true)],
                                    currentTrack: nil, isPlaying: false, position: 0, lastUpdate: 0,
                                    queue: [], volume: 1, allowParticipantControl: true)
            chat.append(LTChatMessage(username: "System", message: "Room \(code) created. Share the code to invite friends.", isSystem: true))
            objectWillChange.send()

        case "join_request":
            // Host approves/rejects — surfaced via the room pending list.
            pendingJoins.append(LTUser(
                userId: JSON.asString(payload["user_id"]) ?? "",
                username: JSON.asString(payload["username"]) ?? "Guest",
                isHost: false, isConnected: true))
            chat.append(LTChatMessage(username: "System", message: "\(JSON.asString(payload["username"]) ?? "Someone") wants to join.", isSystem: true))

        case "join_approved":
            let code = JSON.asString(payload["room_code"]) ?? ""
            userId = JSON.asString(payload["user_id"])
            sessionToken = JSON.asString(payload["session_token"])
            phase = .inRoom(roomCode: code)
            chat.append(LTChatMessage(username: "System", message: "Joined room \(code).", isSystem: true))
            applyState(payload["state"])
            send(type: "request_sync", payload: [:])

        case "join_rejected":
            let reason = JSON.asString(payload["reason"]) ?? "The host declined the request."
            phase = .error(reason)

        case "user_joined":
            let name = JSON.asString(payload["username"]) ?? "Someone"
            chat.append(LTChatMessage(username: "System", message: "\(name) joined.", isSystem: true))

        case "user_left", "user_disconnected":
            let name = JSON.asString(payload["username"]) ?? "Someone"
            chat.append(LTChatMessage(username: "System", message: "\(name) left.", isSystem: true))

        case "user_reconnected":
            let name = JSON.asString(payload["username"]) ?? "Someone"
            chat.append(LTChatMessage(username: "System", message: "\(name) reconnected.", isSystem: true))

        case "host_changed":
            let newHost = JSON.asString(payload["new_host_id"])
            isHost = newHost == userId
            chat.append(LTChatMessage(username: "System", message: "Host transferred.", isSystem: true))

        case "kicked":
            phase = .error("You were removed from the room.")
            disconnect()

        case "sync_state", "sync_playback":
            applyState(payload)

        case "buffer_wait", "buffer_complete":
            break

        case "error":
            let message = JSON.asString(payload["message"]) ?? "Server error"
            chat.append(LTChatMessage(username: "System", message: message, isSystem: true))

        case "pong":
            lastPongAt = Date()
            if let serverTime = JSON.asDouble(payload["server_time"]) {
                serverClockOffset = serverTime - Date().timeIntervalSince1970
            }

        case "chat":
            let name = JSON.asString(payload["username"]) ?? "Guest"
            let text = JSON.asString(payload["message"]) ?? ""
            let host = JSON.asBool(payload["is_host"]) ?? false
            chat.append(LTChatMessage(username: name, message: text, isHost: host))
            if chat.count > 200 { chat.removeFirst(chat.count - 200) }

        case "suggestion_received":
            let track = decodeTrack(payload["track_info"])
            let by = JSON.asString(payload["suggested_by"]) ?? "Guest"
            if let track = track {
                let suggestionId = JSON.asString(payload["suggestion_id"]) ?? UUID().uuidString
                suggestions.append(LTSuggestion(suggestionId: suggestionId, track: track, suggestedBy: by))
            }

        case "suggestion_approved":
            let id = JSON.asString(payload["suggestion_id"]) ?? ""
            suggestions.removeAll { $0.suggestionId == id }

        case "suggestion_rejected":
            let id = JSON.asString(payload["suggestion_id"]) ?? ""
            suggestions.removeAll { $0.suggestionId == id }

        case "room_settings_changed":
            if var state = roomState {
                state.allowParticipantControl = JSON.asBool(payload["allow_participant_control"]) ?? state.allowParticipantControl
                roomState = state
            }

        default:
            break
        }
    }

    @Published var pendingJoins: [LTUser] = []

    private func applyState(_ any: Any?) {
        guard let dict = any as? [String: Any] else { return }
        var users: [LTUser] = []
        if let rawUsers = JSON.asArray(dict["users"]) {
            for user in rawUsers {
                if let userDict = user as? [String: Any] {
                    users.append(LTUser(
                        userId: JSON.asString(userDict["user_id"]) ?? "",
                        username: JSON.asString(userDict["username"]) ?? "Guest",
                        isHost: JSON.asBool(userDict["is_host"]) ?? false,
                        isConnected: JSON.asBool(userDict["is_connected"]) ?? true))
                }
            }
        }
        var queue: [LTTrackInfo] = []
        for item in JSON.asArray(dict["queue"]) ?? [] {
            if let track = decodeTrack(item) { queue.append(track) }
        }
        let state = LTRoomState(
            roomCode: JSON.asString(dict["room_code"]) ?? roomState?.roomCode ?? "",
            hostId: JSON.asString(dict["host_id"]) ?? "",
            users: users,
            currentTrack: decodeTrack(dict["current_track"]),
            isPlaying: JSON.asBool(dict["is_playing"]) ?? false,
            position: JSON.asDouble(dict["position"]) ?? 0,
            lastUpdate: JSON.asDouble(dict["last_update"]) ?? Date().timeIntervalSince1970,
            queue: queue,
            volume: JSON.asDouble(dict["volume"]) ?? 1,
            allowParticipantControl: JSON.asBool(dict["allow_participant_control"]) ?? true)
        roomState = state
    }

    private func decodeTrack(_ any: Any?) -> LTTrackInfo? {
        guard let dict = any as? [String: Any] else { return nil }
        guard let id = JSON.asString(dict["id"]), !id.isEmpty else { return nil }
        return LTTrackInfo(
            id: id,
            title: JSON.asString(dict["title"]) ?? "",
            artist: JSON.asString(dict["artist"]) ?? "",
            album: JSON.asString(dict["album"]),
            duration: JSON.asInt(dict["duration"]) ?? 0,
            thumbnail: JSON.asString(dict["thumbnail"]),
            suggestedBy: JSON.asString(dict["suggested_by"]))
    }

    // MARK: Actions

    private func send(type: String, payload: [String: Any]) {
        let envelope: [String: Any] = ["type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    func approveJoin(userId: String) {
        pendingJoins.removeAll { $0.userId == userId }
        send(type: "approve_join", payload: ["user_id": userId])
    }

    func rejectJoin(userId: String) {
        pendingJoins.removeAll { $0.userId == userId }
        send(type: "reject_join", payload: ["user_id": userId, "reason": "Declined by host"])
    }

    func kickUser(userId: String) {
        send(type: "kick_user", payload: ["user_id": userId])
    }

    func transferHost(to userId: String) {
        send(type: "transfer_host", payload: ["new_host_id": userId])
    }

    func sendChat(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(type: "chat", payload: ["message": trimmed])
        chat.append(LTChatMessage(username: username, message: trimmed))
    }

    func sendPlaybackAction(_ action: PlayAction, trackId: String? = nil, position: Double? = nil, track: LTTrackInfo? = nil, queue: [LTTrackInfo]? = nil) {
        var payload: [String: Any] = ["action": action.rawValue]
        if let trackId = trackId { payload["track_id"] = trackId }
        if let position = position { payload["position"] = position }
        if let track = track { payload["track_info"] = trackDictionary(track) }
        if let queue = queue { payload["queue"] = queue.map(trackDictionary) }
        send(type: "playback_action", payload: payload)
    }

    func suggestTrack(_ song: Song) {
        let track = LTTrackInfo(id: song.id, title: song.title, artist: song.artistsText,
                                album: song.album, duration: song.duration ?? 0,
                                thumbnail: song.thumbnailUrl, suggestedBy: username)
        send(type: "suggest_track", payload: ["track_info": trackDictionary(track)])
    }

    func approveSuggestion(_ suggestion: LTSuggestion) {
        send(type: "approve_suggestion", payload: ["suggestion_id": suggestion.suggestionId])
    }

    func rejectSuggestion(_ suggestion: LTSuggestion) {
        send(type: "reject_suggestion", payload: ["suggestion_id": suggestion.suggestionId])
    }

    func setRoomSettings(allowParticipantControl: Bool) {
        send(type: "update_room_settings", payload: ["allow_participant_control": allowParticipantControl])
    }

    func requestSync() {
        send(type: "request_sync", payload: [:])
    }

    private func trackDictionary(_ track: LTTrackInfo) -> [String: Any] {
        var dict: [String: Any] = [
            "id": track.id, "title": track.title, "artist": track.artist,
            "duration": track.duration,
        ]
        if let album = track.album { dict["album"] = album }
        if let thumbnail = track.thumbnail { dict["thumbnail"] = thumbnail }
        if let suggestedBy = track.suggestedBy { dict["suggested_by"] = suggestedBy }
        return dict
    }

    // MARK: Sync math

    /// Extrapolated playback position from the last sync state (clock-synced like Android).
    var syncedPosition: Double {
        guard let state = roomState, state.isPlaying, state.duration > 0 else {
            return roomState?.position ?? 0
        }
        let elapsed = max(0, Date().timeIntervalSince1970 - state.lastUpdate - serverClockOffset)
        return min(state.position + elapsed, Double(state.duration))
    }
}

extension LTRoomState {
    /// Non-nil when a track is loaded (drives the mini sync bar).
    var duration: Int { currentTrack?.duration ?? 0 }
}
