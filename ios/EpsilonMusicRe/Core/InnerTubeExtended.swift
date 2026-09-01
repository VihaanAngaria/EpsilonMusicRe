import Foundation
import CryptoKit

// MARK: - WEB client (comments + account menu use the desktop web client)

extension YTClients {
    /// WEB — desktop YouTube web client (id 1); comments use it to unlock nested replies.
    static let web = YTClientConfig(
        name: "WEB", version: "2.20260213.00.00", id: "1",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        osName: nil, osVersion: nil, deviceMake: nil, deviceModel: nil, androidSdkVersion: nil)
}

// MARK: - Extra result types

struct CommentItem: Identifiable, Equatable {
    var commentId: String
    var author: String
    var avatar: String?
    var text: String
    var publishedTime: String
    var likeCount: String
    var isLiked: Bool
    var replyCount: Int
    var replies: [CommentItem]
    var repliesToken: String?
    var isReply: Bool

    var id: String { commentId }
}

struct CommentsPage {
    var comments: [CommentItem]
    var continuation: String?
}

struct MediaInfoResult {
    var title: String
    var channelName: String
    var channelId: String?
    var channelThumbnail: String?
    var subscriberCount: String?
    var publishDate: String?
    var viewCount: String?
    var likeCount: String?
    var dislikeCount: Int?
}

struct NewPipePlayerResult {
    var streamUrl: String
    var itag: Int
}

// MARK: - Extended InnerTube API

extension InnerTube {

    static let innertubeApiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    func webBody(_ extra: [String: Any]) -> [String: Any] {
        var body = YTClients.web.context(hl: hl, gl: gl)
        for (k, v) in extra { body[k] = v }
        return body
    }

    // MARK: Account

    func accountMenu() async throws -> Any {
        let body = remixBody([
            "deviceTheme": "DEVICE_THEME_SELECTED",
            "userInterfaceTheme": "USER_INTERFACE_THEME_DARK"
        ])
        return try await post("account/account_menu", body: body, client: YTClients.webRemix)
    }

    /// Mints a guest visitorData token from music.youtube.com/sw.js_data.
    func fetchVisitorData() async -> String? {
        if let existing = AccountManager.shared.visitorData, !existing.isEmpty {
            return existing
        }
        var request = URLRequest(url: URL(string: "https://music.youtube.com/sw.js_data")!, timeoutInterval: 15)
        request.setValue(YTClients.webRemix.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasPrefix(")]}'") { text = String(text.dropFirst(5)) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIndex = trimmed.firstIndex(of: "["), let json = JSON.parse(Data(String(trimmed[startIndex...]).utf8)) else { return nil }
        if let arr = JSON.asArray(JSON.dig(json, 0, 2)) {
            for item in arr {
                if let s = JSON.asString(item), (s.hasPrefix("Cgt") || s.hasPrefix("Cgs")), s.count > 20 {
                    return s
                }
            }
        }
        return nil
    }

    // MARK: Charts / New releases / generic browse

    func charts() async throws -> [Shelf] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_charts", "params": "ggMGCgQIgAQ%3D"]), client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
        var shelves = Self.parseShelfContents(contents)
        // Chart grids (musicResponsiveListItemRenderer rows with chart position columns).
        if let sections = JSON.asArray(contents) {
            for section in sections {
                guard let grid = JSON.dig(section, "gridRenderer") else { continue }
                let title = Self.runsText(JSON.dig(grid, "header", "gridHeaderRenderer", "title", "runs")) ?? "Charts"
                var items: [MediaGridItem] = []
                if let gridItems = JSON.asArray(JSON.dig(grid, "items")) {
                    for gi in gridItems {
                        if let renderer = JSON.dig(gi, "musicTwoRowItemRenderer"), let item = Self.parseTwoRowItem(renderer) {
                            items.append(item)
                        }
                    }
                }
                if !items.isEmpty {
                    shelves.append(Shelf(title: title, subtitle: nil, items: items))
                }
            }
        }
        return shelves
    }

    func newReleaseAlbums() async throws -> [MediaGridItem] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_new_releases_albums"]), client: YTClients.webRemix)
        var items: [MediaGridItem] = []
        let sections = JSON.asArray(JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")) ?? []
        for section in sections {
            guard let grid = JSON.dig(section, "gridRenderer") else { continue }
            if let gridItems = JSON.asArray(JSON.dig(grid, "items")) {
                for gi in gridItems {
                    if let two = JSON.dig(gi, "musicTwoRowItemRenderer"), let item = Self.parseTwoRowItem(two) {
                        items.append(item)
                    } else if let list = JSON.dig(gi, "musicResponsiveListItemRenderer"), let item = Self.parseListItem(list) {
                        items.append(item)
                    }
                }
            }
        }
        return items
    }

    /// Generic browse with params — mood chips, YouTube browse pages.
    func browse(browseId: String, params: String?) async throws -> [Shelf] {
        var extra: [String: Any] = ["browseId": browseId]
        if let params = params, !params.isEmpty { extra["params"] = params }
        let json = try await post("browse", body: remixBody(extra), client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
            ?? JSON.dig(json, "contents", "twoColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
        return Self.parseShelfContents(contents)
    }

    /// Home page with chip param (localized feeds).
    func home(params: String?) async throws -> [Shelf] {
        var extra: [String: Any] = ["browseId": "FEmusic_home"]
        if let params = params, !params.isEmpty { extra["params"] = params }
        let json = try await post("browse", body: remixBody(extra), client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
        return Self.parseShelfContents(contents)
    }

    /// Home feed chip params (first chip = default, others = language variants).
    func homeChips() async throws -> [(title: String, params: String?)] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_home"]), client: YTClients.webRemix)
        let chips = JSON.asArray(JSON.dig(json, "header", "chipCloudRenderer", "chips")) ?? []
        var out: [(String, String?)] = []
        for chip in chips {
            let title = Self.runsText(JSON.dig(chip, "chipCloudChipRenderer", "text", "runs")) ?? ""
            let params = JSON.asString(JSON.dig(chip, "chipCloudChipRenderer", "navigationEndpoint", "browseEndpoint", "params"))
            if !title.isEmpty { out.append((title, params)) }
        }
        return out
    }

    // MARK: Library / history (logged-in YouTube Music library)

    func library(browseId: String) async throws -> [Shelf] {
        let json = try await post("browse", body: remixBody(["browseId": browseId]), client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
        return Self.parseShelfContents(contents)
    }

    /// Liked songs ("LM" playlist) — requires login.
    func likedSongs() async throws -> MediaPage {
        try await playlistOrAlbum(browseId: "VLLM", isPlaylist: true)
    }

    /// YouTube Music watch history (sections of songs).
    func musicHistory() async throws -> [Shelf] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_history"]), client: YTClients.webRemix)
        let sections = JSON.asArray(JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")) ?? []
        var shelves: [Shelf] = []
        for section in sections {
            guard let shelf = JSON.dig(section, "musicShelfRenderer") else { continue }
            let title = Self.runsText(JSON.dig(shelf, "title", "runs")) ?? "History"
            var items: [MediaGridItem] = []
            if let list = JSON.asArray(JSON.dig(shelf, "contents")) {
                for item in list {
                    if let renderer = JSON.dig(item, "musicResponsiveListItemRenderer"),
                       let song = Self.parseListItemSong(renderer) {
                        items.append(.song(song))
                    }
                }
            }
            if !items.isEmpty { shelves.append(Shelf(title: title, subtitle: nil, items: items)) }
        }
        return shelves
    }

    /// Register playback on the YouTube watch-history tracker (MusicService parity).
    func registerPlayback(videostatsUrl: String?, playlistId: String?) async {
        guard var baseUrl = videostatsUrl else { return }
        baseUrl = baseUrl.replacingOccurrences(of: "https://s.youtube.com", with: "https://music.youtube.com")
        let cpn = Self.randomCpn()
        var components = URLComponents(string: baseUrl)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "ver", value: "2"))
        items.append(URLQueryItem(name: "c", value: "WEB_REMIX"))
        items.append(URLQueryItem(name: "cpn", value: cpn))
        if let playlistId = playlistId {
            items.append(URLQueryItem(name: "list", value: playlistId))
            items.append(URLQueryItem(name: "referrer", value: "https://music.youtube.com/playlist?list=\(playlistId)"))
        }
        components?.queryItems = items
        guard let url = components?.url else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        _ = try? await session.data(for: request)
    }

    static func randomCpn() -> String {
        let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        var out = ""
        for _ in 0..<16 {
            out.append(alphabet.randomElement() ?? "a")
        }
        return out
    }

    // MARK: Likes / subscriptions / feedback

    func likeVideo(_ videoId: String, like: Bool) async throws {
        let path = like ? "like/like" : "like/removelike"
        _ = try await post(path, body: remixBody(["target": ["videoId": videoId]]), client: YTClients.webRemix)
    }

    func likePlaylist(_ playlistId: String, like: Bool) async throws {
        let path = like ? "like/like" : "like/removelike"
        _ = try await post(path, body: remixBody(["target": ["playlistId": playlistId]]), client: YTClients.webRemix)
    }

    func subscribeChannel(_ channelId: String, subscribe: Bool) async throws {
        let path = subscribe ? "subscription/subscribe" : "subscription/unsubscribe"
        _ = try await post(path, body: remixBody(["channelIds": [channelId]]), client: YTClients.webRemix)
    }

    func feedback(tokens: [String]) async throws {
        _ = try await post("feedback", body: remixBody([
            "feedbackTokens": tokens,
            "isFeedbackTokenUnencrypted": false,
            "shouldMerge": false
        ]), client: YTClients.webRemix)
    }

    /// Library add/remove tokens from the current song's `next` panel
    /// (toggleMenuServiceItemRenderer: BOOKMARK* icons).
    func libraryToggleTokens(videoId: String) async -> (add: String?, remove: String?) {
        let body = remixBody(["isRoot": true, "videoId": videoId])
        guard let json = try? await post("next", body: body, client: YTClients.webRemix) else { return (nil, nil) }
        // Walk all playlistPanelVideoRenderers and menu items for feedback tokens.
        var addToken: String?
        var removeToken: String?
        func walk(_ any: Any?) {
            guard let dict = any as? [String: Any] else { return }
            if let renderer = dict["toggleMenuServiceItemRenderer"] as? [String: Any] {
                let iconName = JSON.asString(JSON.dig(renderer, "defaultIcon", "iconType")) ?? ""
                let defaultToken = JSON.asString(JSON.dig(renderer, "defaultServiceEndpoint", "feedbackEndpoint", "feedbackToken"))
                let toggledToken = JSON.asString(JSON.dig(renderer, "toggledServiceEndpoint", "feedbackEndpoint", "feedbackToken"))
                if iconName == "BOOKMARK_BORDER" || iconName == "LIBRARY_ADD" {
                    addToken = defaultToken ?? addToken
                    removeToken = toggledToken ?? removeToken
                } else if iconName == "BOOKMARK" || iconName == "LIBRARY_SAVED" || iconName == "LIBRARY_REMOVE" {
                    addToken = toggledToken ?? addToken
                    removeToken = defaultToken ?? removeToken
                }
            }
            for (key, value) in dict {
                if key != "toggleMenuServiceItemRenderer" {
                    walk(value)
                }
            }
        }
        walk(json)
        return (addToken, removeToken)
    }

    // MARK: Playlist CRUD (edit_playlist actions)

    func createPlaylist(title: String, privacy: String = "PRIVATE", videoIds: [String] = []) async throws -> String? {
        var body: [String: Any] = ["title": title, "privacyStatus": privacy]
        if !videoIds.isEmpty { body["videoIds"] = videoIds }
        let json = try await post("playlist/create", body: remixBody(body), client: YTClients.webRemix)
        return JSON.asString(JSON.dig(json, "playlistId"))
    }

    func deletePlaylist(_ playlistId: String) async throws {
        _ = try await post("playlist/delete", body: remixBody(["playlistId": Self.stripVL(playlistId)]), client: YTClients.webRemix)
    }

    func renamePlaylist(_ playlistId: String, to name: String) async throws {
        try await editPlaylist(playlistId, actions: [["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": name]])
    }

    func addToPlaylist(_ playlistId: String, videoId: String) async throws {
        try await editPlaylist(playlistId, actions: [["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId]])
    }

    func removeFromPlaylist(_ playlistId: String, videoId: String, setVideoId: String) async throws {
        try await editPlaylist(playlistId, actions: [["action": "ACTION_REMOVE_VIDEO", "setVideoId": setVideoId, "removedVideoId": videoId]])
    }

    private func editPlaylist(_ playlistId: String, actions: [[String: Any]]) async throws {
        _ = try await post("browse/edit_playlist", body: remixBody([
            "playlistId": Self.stripVL(playlistId),
            "actions": actions
        ]), client: YTClients.webRemix)
    }

    static func stripVL(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    // MARK: Transcript (subtitle-based lyrics)

    func transcript(videoId: String) async -> Lyrics? {
        let params = "\n\u{000b}\(videoId)"
        let encoded = Data(params.utf8).base64EncodedString()
        var query = "key=\(Self.innertubeApiKey)"
        if let escaped = encoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            query = "key=\(Self.innertubeApiKey)&params=\(escaped)"
        }
        guard let url = URL(string: "https://music.youtube.com/youtubei/v1/get_transcript?\(query)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(YTClients.webRemix.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(YTClients.webRemix.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(YTClients.webRemix.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        let body = webBody(["params": encoded])
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = JSON.parse(data) else { return nil }
        return Self.parseTranscript(json)
    }

    static func parseTranscript(_ json: Any) -> Lyrics? {
        // Walk the transcript body for cueGroups: transcriptRenderer.body.transcriptBodyRenderer.cueGroups[]
        var lines: [LyricsLine] = []
        func collect(_ any: Any?) {
            guard let dict = any as? [String: Any] else { return }
            if let cue = dict["transcriptCueGroupRenderer"] as? [String: Any] {
                let timeText = JSON.asString(JSON.dig(cue, "cues", 0, "transcriptCueRenderer", "startMs")) ?? "0"
                let text = Self.runsText(JSON.dig(cue, "cues", 0, "transcriptCueRenderer", "cue", "simpleText"))
                    ?? Self.runsText(JSON.dig(cue, "cues", 0, "transcriptCueRenderer", "cue", "runs"))
                    ?? ""
                if let ms = Double(timeText), !text.isEmpty {
                    lines.append(LyricsLine(time: ms / 1000.0, text: text))
                }
            }
            for value in dict.values { collect(value) }
        }
        collect(json)
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines.sorted { $0.time < $1.time }, isSynced: true, sourceName: "YouTube")
    }

    // MARK: Comments (WEB client, 3-token bootstrap + framework merge)

    func comments(videoId: String) async throws -> CommentsPage {
        let body = webBody(["videoId": videoId])
        let json = try await post("next", body: body, client: YTClients.web)

        // Priority 1: direct continuationItemRenderer in results contents.
        var token: String?
        let results = JSON.asArray(JSON.dig(json, "contents", "twoColumnWatchNextResults", "results", "results", "contents"))
        if let results = results {
            for content in results {
                if let t = JSON.asString(JSON.dig(content, "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token")) {
                    token = t; break
                }
            }
        }
        // Priority 2: itemSectionRenderer → contents → continuationItemRenderer.
        if token == nil, let results = results {
            for section in results {
                if let inner = JSON.asArray(JSON.dig(section, "itemSectionRenderer", "contents")) {
                    for item in inner {
                        if let t = JSON.asString(JSON.dig(item, "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token")) {
                            token = t; break
                        }
                    }
                    if token != nil { break }
                }
            }
        }
        // Priority 3: engagement panel "engagement-panel-comments-section".
        if token == nil, let panels = JSON.asArray(JSON.dig(json, "engagementPanels")) {
            for panel in panels {
                let identifier = JSON.asString(JSON.dig(panel, "engagementPanelSectionListRenderer", "panelIdentifier"))
                if identifier == "engagement-panel-comments-section" {
                    token = findContinuationToken(JSON.dig(panel, "engagementPanelSectionListRenderer", "content"))
                }
            }
        }
        guard let token = token else { return CommentsPage(comments: [], continuation: nil) }
        return try await commentContinuation(token)
    }

    private func findContinuationToken(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        if let t = JSON.asString(JSON.dig(dict, "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token")) {
            return t
        }
        if let t = JSON.asString(JSON.dig(dict, "itemSectionRenderer", "contents", 0, "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token")) {
            return t
        }
        for value in dict.values {
            if let t = findContinuationToken(value) { return t }
        }
        return nil
    }

    func commentContinuation(_ token: String) async throws -> CommentsPage {
        let body = webBody(["continuation": token])
        let json = try await post("next", body: body, client: YTClients.web)
        return Self.parseCommentResponse(json)
    }

    func commentReplies(_ token: String) async throws -> CommentsPage {
        try await commentContinuation(token)
    }

    static func parseCommentResponse(_ json: Any) -> CommentsPage {
        var comments: [CommentItem] = []
        var nextToken: String?

        // Legacy renderers.
        var legacyThreads: [String: (CommentItem, String?)] = [:] // id → (item, replyToken)
        var order: [String] = []

        // Framework entity payloads.
        var entityPayloads: [String: [String: Any]] = [:]  // commentId → payload
        var toolbarStates: [String: [String: Any]] = [:]   // key → state
        var toolbarSurfaces: [String: [String: Any]] = [:]

        // Collect framework updates.
        if let mutations = JSON.asArray(JSON.dig(json, "frameworkUpdates", "entityBatchUpdate", "mutations")) {
            for mutation in mutations {
                guard let payload = JSON.asDict(JSON.dig(mutation, "payload")) else { continue }
                if let comment = JSON.asDict(payload["commentEntityPayload"]) {
                    let id = JSON.asString(JSON.dig(comment, "properties", "commentId")) ?? ""
                    if !id.isEmpty { entityPayloads[id] = comment }
                }
                if let state = JSON.asDict(payload["engagementToolbarStateEntityPayload"]) {
                    let key = JSON.asString(state["key"]) ?? ""
                    if !key.isEmpty { toolbarStates[key] = state }
                }
                if let surface = JSON.asDict(payload["engagementToolbarSurfaceEntityPayload"]) {
                    let key = JSON.asString(surface["key"]) ?? ""
                    if !key.isEmpty { toolbarSurfaces[key] = surface }
                }
            }
        }

        func parseCommentRenderer(_ renderer: [String: Any], isReply: Bool) -> CommentItem? {
            let id = JSON.asString(renderer["commentId"]) ?? UUID().uuidString
            var author = JSON.asString(JSON.dig(renderer, "authorText", "runs", 0, "text")) ?? ""
            let avatar = Self.thumbnailUrl(JSON.dig(renderer, "authorThumbnail", "thumbnails"))
            let text = Self.runsText(JSON.dig(renderer, "contentText", "runs")) ?? ""
            let published = JSON.asString(JSON.dig(renderer, "publishedTimeText", "runs", 0, "text")) ?? ""
            let votes = JSON.asString(JSON.dig(renderer, "voteCount", "runs", 0, "text")) ?? ""
            let voteStatus = JSON.asString(renderer["voteStatus"]) ?? "INDIFFERENT"
            let replyCount = JSON.asInt(renderer["replyCount"]) ?? 0
            if author.isEmpty { author = "Unknown" }
            return CommentItem(commentId: id, author: author, avatar: avatar, text: text,
                               publishedTime: published, likeCount: votes,
                               isLiked: voteStatus == "UPVOTE", replyCount: replyCount,
                               replies: [], repliesToken: nil, isReply: isReply)
        }

        func walk(_ any: Any?, isReply: Bool) {
            guard let dict = any as? [String: Any] else { return }
            if let thread = JSON.asDict(dict["commentThreadRenderer"]) {
                var item: CommentItem?
                var replyToken: String?
                if let renderer = JSON.asDict(JSON.dig(thread, "comment", "commentRenderer")) {
                    item = parseCommentRenderer(renderer, isReply: false)
                }
                if item == nil, let vm = JSON.asDict(JSON.dig(thread, "comment", "commentViewModel", "commentViewModel")) {
                    let id = JSON.asString(vm["commentId"]) ?? UUID().uuidString
                    item = CommentItem(commentId: id, author: "…", avatar: nil, text: "",
                                       publishedTime: "", likeCount: "", isLiked: false,
                                       replyCount: 0, replies: [], repliesToken: nil, isReply: false)
                }
                if let replies = JSON.asDict(thread["commentRepliesRenderer"]) {
                    // reply token, 3 locations.
                    var token = JSON.asString(JSON.dig(replies, "contents", 0, "continuationItemRenderer", "continuationEndpoint", "continuationCommand", "token"))
                    if token == nil {
                        token = JSON.asString(JSON.dig(replies, "viewReplies", "buttonRenderer", "command", "continuationCommand", "token"))
                    }
                    if token == nil {
                        token = JSON.asString(JSON.dig(replies, "viewReplies", "buttonRenderer", "navigationEndpoint", "continuationCommand", "token"))
                    }
                    replyToken = token
                    // Nested inline replies.
                    if let contents = JSON.asArray(replies["contents"]) {
                        for content in contents {
                            if let renderer = JSON.asDict(JSON.dig(content, "commentRenderer")) {
                                if let reply = parseCommentRenderer(renderer, isReply: true) {
                                    item?.replies.append(reply)
                                }
                            }
                        }
                    }
                }
                if var finalItem = item {
                    // Merge framework payload (preferred for text/author/time/likes).
                    if let payload = entityPayloads[finalItem.commentId] {
                        let text = JSON.asString(JSON.dig(payload, "properties", "content", "content"))
                        let author = JSON.asString(JSON.dig(payload, "author", "displayName"))
                        let published = JSON.asString(JSON.dig(payload, "properties", "publishedTime"))
                        let avatar = JSON.asString(JSON.dig(payload, "author", "avatarThumbnailUrl"))
                        let toolbarKey = JSON.asString(JSON.dig(payload, "properties", "toolbarStateKey")) ?? ""
                        let surfaceKey = JSON.asString(JSON.dig(payload, "properties", "toolbarSurfaceKey")) ?? ""
                        var likes = JSON.asString(JSON.dig(payload, "toolbar", "likeCountNotliked")) ?? ""
                        if likes.isEmpty, let surface = toolbarSurfaces[surfaceKey] {
                            likes = JSON.asString(JSON.dig(surface, "toolbar", "likeCountNotliked")) ?? ""
                        }
                        let likeState = JSON.asString(JSON.dig(toolbarStates[toolbarKey], "likeState")) ?? ""
                        if let t = text, !t.isEmpty { finalItem.text = t }
                        if let a = author, !a.isEmpty { finalItem.author = a }
                        if let p = published, !p.isEmpty { finalItem.publishedTime = p }
                        if let av = avatar, !av.isEmpty { finalItem.avatar = av }
                        if !likes.isEmpty { finalItem.likeCount = likes }
                        finalItem.isLiked = likeState == "TOOLBAR_LIKE_STATE_LIKE"
                    }
                    finalItem.repliesToken = replyToken
                    if !legacyThreads.keys.contains(finalItem.commentId) {
                        order.append(finalItem.commentId)
                    }
                    legacyThreads[finalItem.commentId] = (finalItem, replyToken)
                }
            } else if let renderer = JSON.asDict(dict["commentRenderer"]) {
                if let item = parseCommentRenderer(renderer, isReply: isReply) {
                    var finalItem = item
                    if let payload = entityPayloads[finalItem.commentId] {
                        let text = JSON.asString(JSON.dig(payload, "properties", "content", "content"))
                        let author = JSON.asString(JSON.dig(payload, "author", "displayName"))
                        if let t = text, !t.isEmpty { finalItem.text = t }
                        if let a = author, !a.isEmpty { finalItem.author = a }
                    }
                    if !legacyThreads.keys.contains(finalItem.commentId) {
                        order.append(finalItem.commentId)
                    }
                    legacyThreads[finalItem.commentId] = (finalItem, nil)
                }
            } else if let cont = JSON.asDict(dict["continuationItemRenderer"]) {
                if let t = JSON.asString(JSON.dig(cont, "continuationEndpoint", "continuationCommand", "token")) {
                    nextToken = nextToken ?? t
                }
                if let t = JSON.asString(JSON.dig(cont, "button", "buttonRenderer", "command", "continuationCommand", "token")) {
                    nextToken = nextToken ?? t
                }
                if let t = JSON.asString(JSON.dig(cont, "button", "buttonRenderer", "navigationEndpoint", "continuationCommand", "token")) {
                    nextToken = nextToken ?? t
                }
            }
            for (key, value) in dict {
                if key == "commentThreadRenderer" || key == "commentRenderer" || key == "continuationItemRenderer" { continue }
                walk(value, isReply: isReply)
            }
        }

        if let endpoints = JSON.asArray(JSON.dig(json, "onResponseReceivedEndpoints")) {
            for endpoint in endpoints {
                let reloadItems = JSON.asArray(JSON.dig(endpoint, "reloadContinuationItemsCommand", "continuationItems"))
                let appendItems = JSON.asArray(JSON.dig(endpoint, "appendContinuationItemsAction", "continuationItems"))
                for item in reloadItems ?? [] { walk(item, isReply: false) }
                for item in appendItems ?? [] { walk(item, isReply: false) }
            }
        }

        comments = order.compactMap { legacyThreads[$0]?.0 }
        return CommentsPage(comments: comments, continuation: nextToken)
    }

    // MARK: Media info + dislikes (player details sheet)

    func mediaInfo(videoId: String) async -> MediaInfoResult? {
        let body = webBody(["videoId": videoId])
        guard let json = try? await post("next", body: body, client: YTClients.web) else { return nil }
        let contents = JSON.asArray(JSON.dig(json, "contents", "twoColumnWatchNextResults", "results", "results", "contents")) ?? []
        var result = MediaInfoResult(title: "", channelName: "", channelId: nil, channelThumbnail: nil,
                                     subscriberCount: nil, publishDate: nil, viewCount: nil, likeCount: nil, dislikeCount: nil)
        for content in contents {
            if let primary = JSON.asDict(content["videoPrimaryInfoRenderer"]) {
                result.title = Self.runsText(JSON.dig(primary, "title", "runs")) ?? result.title
                result.publishDate = Self.runsText(JSON.dig(primary, "dateText", "runs"))
                if let views = Self.runsText(JSON.dig(primary, "viewCount", "videoViewCountRenderer", "viewCount", "runs")) {
                    result.viewCount = views
                }
            }
            if let secondary = JSON.asDict(content["videoSecondaryInfoRenderer"]) {
                let owner = JSON.dig(secondary, "owner", "videoOwnerRenderer")
                result.channelName = Self.runsText(JSON.dig(owner, "title", "runs")) ?? result.channelName
                result.channelId = JSON.asString(JSON.dig(owner, "navigationEndpoint", "browseEndpoint", "browseId"))
                let thumbs = JSON.asArray(JSON.dig(owner, "thumbnail", "thumbnails")) ?? []
                result.channelThumbnail = Self.thumbnailUrl(thumbs)
                result.subscriberCount = Self.runsText(JSON.dig(secondary, "subscriberCountText", "runs"))
            }
        }
        // ReturnYouTubeDislike votes.
        if let url = URL(string: "https://returnyoutubedislikeapi.com/Votes?videoId=\(videoId)") {
            if let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let json = JSON.parse(data) {
                result.dislikeCount = JSON.asInt(JSON.dig(json, "dislikes"))
                if let likes = JSON.asInt(JSON.dig(json, "likes")) {
                    result.likeCount = "\(likes)"
                }
            }
        }
        return result
    }

    // MARK: Lyrics endpoint (YouTube Music's own lyrics — MusicMultiRowListItemRenderer)

    func youtubeMusicLyrics(videoId: String) async -> Lyrics? {
        let body = remixBody(["isRoot": true, "videoId": videoId])
        guard let json = try? await post("next", body: body, client: YTClients.webRemix) else { return nil }
        // find lyricsEndpoint in the panels
        var browseId: String?
        var params: String?
        func findLyricsEndpoint(_ any: Any?) {
            guard let dict = any as? [String: Any] else { return }
            if let endpoint = JSON.asDict(dict["lyricsEndpoint"]) {
                browseId = JSON.asString(endpoint["browseId"]) ?? browseId
                params = JSON.asString(endpoint["params"]) ?? params
            }
            for (key, value) in dict {
                if key != "lyricsEndpoint" { findLyricsEndpoint(value) }
            }
        }
        findLyricsEndpoint(json)
        guard let bid = browseId else { return nil }
        var extra: [String: Any] = ["browseId": bid]
        if let p = params { extra["params"] = p }
        guard let lyricsJson = try? await post("browse", body: remixBody(extra), client: YTClients.webRemix) else { return nil }
        var lines: [LyricsLine] = []
        func collect(_ any: Any?) {
            guard let dict = any as? [String: Any] else { return }
            if let renderer = JSON.asDict(dict["musicMultiRowListItemRenderer"]) {
                let description = Self.runsText(JSON.dig(renderer, "description", "runs"))
                if let text = description, !text.isEmpty {
                    lines.append(LyricsLine(time: -1, text: text))
                }
            } else {
                for value in dict.values { collect(value) }
            }
        }
        collect(lyricsJson)
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines, isSynced: false, sourceName: "YouTube Music")
    }
}
