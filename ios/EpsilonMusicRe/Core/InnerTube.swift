import Foundation

// MARK: - Errors

enum InnerTubeError: LocalizedError {
    case network(String)
    case streamUnavailable(String)
    case parseError(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .network(let msg): return "Network error: \(msg)"
        case .streamUnavailable(let msg): return msg
        case .parseError(let msg): return "Couldn't read response: \(msg)"
        case .badResponse: return "Unexpected response from YouTube Music"
        }
    }
}

// MARK: - Client definitions

/// Swift port of the innertube module (com.music.innertube) — the YouTube Music
/// data layer. Mirrors the Android client's request shapes so both platforms
/// talk to the service identically.
struct YTClientConfig {
    let name: String
    let version: String
    let id: String
    let userAgent: String
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?
    let androidSdkVersion: String?

    /// Client context JSON for the request body.
    func context(hl: String, gl: String) -> [String: Any] {
        var client: [String: Any] = [
            "clientName": name,
            "clientVersion": version,
            "hl": hl,
            "gl": gl,
        ]
        if let v = osName { client["osName"] = v }
        if let v = osVersion { client["osVersion"] = v }
        if let v = deviceMake { client["deviceMake"] = v }
        if let v = deviceModel { client["deviceModel"] = v }
        if let v = androidSdkVersion { client["androidSdkVersion"] = v }
        return ["client": client]
    }
}

enum YTClients {
    /// WEB_REMIX — music.youtube.com web client, used for browse/search/next (mirrors Kotlin WEB_REMIX).
    static let webRemix = YTClientConfig(
        name: "WEB_REMIX", version: "1.20260213.01.00", id: "67",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        osName: nil, osVersion: nil, deviceMake: nil, deviceModel: nil, androidSdkVersion: nil)

    /// ANDROID_VR 1.65.10 — yt-dlp pin; returns whole-file progressive streams without poToken.
    static let androidVR165 = YTClientConfig(
        name: "ANDROID_VR", version: "1.65.10", id: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        osName: "Android", osVersion: "12L", deviceMake: "Oculus", deviceModel: "Quest 3", androidSdkVersion: "32")

    /// ANDROID_VR 1.43.32 — older version-gated fallback, also whole-file capable.
    static let androidVR143 = YTClientConfig(
        name: "ANDROID_VR", version: "1.43.32", id: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android", osVersion: "12", deviceMake: "Oculus", deviceModel: "Quest 3", androidSdkVersion: "32")

    /// IOS — last resort; usually only a ~1 MiB preview stream.
    static let ios = YTClientConfig(
        name: "IOS", version: "21.03.1", id: "5",
        userAgent: "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
        osName: nil, osVersion: "18.2.22C152", deviceMake: nil, deviceModel: nil, androidSdkVersion: nil)
}

// MARK: - Result types

struct ResolvedStream {
    let url: URL
    let duration: Int?
    let clientName: String
    var loudnessDb: Double?
    var codec: String?
    var bitrate: Int?
    var sampleRate: Int?
    var videostatsUrl: String?

    init(url: URL, duration: Int?, clientName: String,
         loudnessDb: Double? = nil, codec: String? = nil, bitrate: Int? = nil,
         sampleRate: Int? = nil, videostatsUrl: String? = nil) {
        self.url = url
        self.duration = duration
        self.clientName = clientName
        self.loudnessDb = loudnessDb
        self.codec = codec
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.videostatsUrl = videostatsUrl
    }
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case songs, videos, artists, albums, communityPlaylists, featuredPlaylists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs: return "Songs"
        case .videos: return "Videos"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .communityPlaylists: return "Community playlists"
        case .featuredPlaylists: return "Featured playlists"
        }
    }

    /// Encoded `params` values — byte-identical to the Kotlin SearchFilter constants.
    var params: String {
        switch self {
        case .songs: return "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        case .videos: return "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
        case .artists: return "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
        case .albums: return "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        case .featuredPlaylists: return "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"
        case .communityPlaylists: return "EgeKAQQoAEABagoQAxAEEAoQCRAF"
        }
    }
}

struct SearchResult {
    var items: [MediaGridItem]
    var songs: [Song]
    var continuation: String?
}

struct MediaPage {
    var title: String
    var subtitle: String?
    var thumbnail: String?
    var songs: [Song]
    var continuation: String?
    var radioPlaylistId: String?
    var isPlaylist: Bool
    var browseId: String
}

struct ArtistPage {
    var artist: ArtistItem
    var songs: [Song]
    var shelves: [Shelf]
    var radioPlaylistId: String?
}

// MARK: - Client

final class InnerTube {

    static let shared = InnerTube()
    private init() {}

    let session: URLSession = .shared
    let hl = "en"
    let gl = "US"

    // MARK: Request plumbing

    func post(_ endpoint: String, body: [String: Any], client: YTClientConfig, query: [String: String] = [:]) async throws -> Any {
        var urlString = "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false"
        for (key, value) in query {
            urlString += "&\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }
        guard let url = URL(string: urlString) else {
            throw InnerTubeError.network("bad endpoint")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(client.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "X-Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        // Logged-in requests carry the account cookie + SAPISIDHASH authorization
        // (Android `loginSupported` parity) and the visitor id header.
        if client.name == "WEB_REMIX", let headers = AccountManager.shared.authHeaders() {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let visitorData = AccountManager.shared.visitorData, !visitorData.isEmpty {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        var finalBody = body
        if client.name == "WEB_REMIX", let behalf = AccountManager.shared.onBehalfOfUser {
            if var context = finalBody["context"] as? [String: Any] {
                var user = context["user"] as? [String: Any] ?? [:]
                user["onBehalfOfUser"] = behalf
                context["user"] = user
                finalBody["context"] = context
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: finalBody, options: [])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw InnerTubeError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw InnerTubeError.network("HTTP \(http.statusCode)")
            }
            guard let json = JSON.parse(data) else { throw InnerTubeError.badResponse }
            return json
        } catch let e as InnerTubeError {
            throw e
        } catch {
            throw InnerTubeError.network(error.localizedDescription)
        }
    }

    func remixBody(_ extra: [String: Any]) -> [String: Any] {
        var body = YTClients.webRemix.context(hl: hl, gl: gl)
        for (k, v) in extra { body[k] = v }
        return body
    }

    // MARK: Search

    func search(query: String, filter: SearchFilter) async throws -> SearchResult {
        let json = try await post("search", body: remixBody(["query": query, "params": filter.params]), client: YTClients.webRemix)
        return try parseSearch(json)
    }

    func searchContinuation(_ token: String) async throws -> SearchResult {
        let json = try await post("search", body: remixBody(["query": ""]), client: YTClients.webRemix, query: ["continuation": token, "ctoken": token])
        return try parseSearch(json)
    }

    func suggestions(query: String) async throws -> [String] {
        let json = try await post("music/get_search_suggestions", body: remixBody(["input": query]), client: YTClients.webRemix)
        var out: [String] = []
        if let sections = JSON.asArray(JSON.dig(json, "contents", "searchSuggestionsSectionRenderer", "contents")) {
            for section in sections {
                if let text = JSON.asString(JSON.dig(section, "searchSuggestionRenderer", "suggestion", "runs", 0, "text")),
                   !text.isEmpty {
                    out.append(text)
                }
            }
        }
        return out
    }

    // MARK: Stream resolution

    /// Resolves a playable progressive stream URL, mirroring the Android client's
    /// fallback order: ANDROID_VR 1.65.10 -> ANDROID_VR 1.43.32 -> IOS.
    func resolveStream(videoId: String) async throws -> ResolvedStream {
        var lastReason = "No playable stream returned"
        for client in [YTClients.androidVR165, YTClients.androidVR143, YTClients.ios] {
            let body = client.context(hl: hl, gl: gl)
            var fullBody = body
            fullBody["videoId"] = videoId
            fullBody["contentCheckOk"] = true
            fullBody["racyCheckOk"] = true
            do {
                let json = try await post("player", body: fullBody, client: client)
                // playability check
                let status = JSON.asString(JSON.dig(json, "playabilityStatus", "status")) ?? ""
                if status != "OK" {
                    let reason = JSON.asString(JSON.dig(json, "playabilityStatus", "reason")) ?? status
                    if !reason.isEmpty { lastReason = reason }
                    continue
                }
                if let stream = Self.pickAudioStream(json, clientName: client.name) {
                    return stream
                }
            } catch {
                // try next client
            }
        }
        throw InnerTubeError.streamUnavailable(lastReason)
    }

    static func pickAudioStream(_ json: Any, clientName: String) -> ResolvedStream? {
        let adaptive = JSON.asArray(JSON.dig(json, "streamingData", "adaptiveFormats")) ?? []
        let formats = JSON.asArray(JSON.dig(json, "streamingData", "formats")) ?? []

        // Prefer itag 140 (AAC 128k m4a) — AVPlayer's most reliable remote format.
        let loudness = JSON.asDouble(JSON.dig(json, "playerConfig", "audioConfig", "loudnessDb"))
        let videostats = JSON.asString(JSON.dig(json, "playbackTracking", "videostatsPlaybackUrl", "baseUrl"))
        func fromList(_ list: [Any], wantedItags: [Int], audioOnly: Bool) -> ResolvedStream? {
            for itag in wantedItags {
                for fmt in list {
                    guard JSON.asInt(JSON.dig(fmt, "itag")) == itag else { continue }
                    if let urlString = JSON.asString(JSON.dig(fmt, "url")), let url = URL(string: urlString) {
                        let duration = JSON.asInt(JSON.dig(fmt, "approxDurationMs")).map { $0 / 1000 }
                        return ResolvedStream(url: url, duration: duration, clientName: clientName,
                                              loudnessDb: loudness,
                                              codec: JSON.asString(JSON.dig(fmt, "codecs")),
                                              bitrate: JSON.asInt(JSON.dig(fmt, "bitrate")),
                                              sampleRate: JSON.asInt(JSON.dig(fmt, "audioSampleRate")),
                                              videostatsUrl: videostats)
                    }
                }
            }
            // Any audio-only format as fallback (last entries = lowest priority).
            if audioOnly {
                for fmt in list.reversed() {
                    let mime = JSON.asString(JSON.dig(fmt, "mimeType")) ?? ""
                    if mime.hasPrefix("audio/mp4"), let urlString = JSON.asString(JSON.dig(fmt, "url")),
                       let url = URL(string: urlString) {
                        let duration = JSON.asInt(JSON.dig(fmt, "approxDurationMs")).map { $0 / 1000 }
                        return ResolvedStream(url: url, duration: duration, clientName: clientName,
                                              loudnessDb: loudness,
                                              codec: JSON.asString(JSON.dig(fmt, "codecs")),
                                              bitrate: JSON.asInt(JSON.dig(fmt, "bitrate")),
                                              sampleRate: JSON.asInt(JSON.dig(fmt, "audioSampleRate")),
                                              videostatsUrl: videostats)
                    }
                }
            }
            return nil
        }

        // itag 140 = audio/mp4 128k, 139 = audio/mp4 48k low quality fallback.
        if let s = fromList(adaptive, wantedItags: [140, 139], audioOnly: true) { return s }
        // itag 18 = mp4 with audio (video+audio muxed) — bigger, but playable.
        if let s = fromList(formats, wantedItags: [18], audioOnly: false) { return s }
        return nil
    }

    // MARK: Radio / related / queue

    /// Radio for a song — the "RDAMVM<videoId>" autoplay playlist trick used by the Android app.
    func radio(videoId: String) async throws -> [Song] {
        if let songs = try? await queue(playlistId: "RDAMVM" + videoId), !songs.isEmpty {
            return songs
        }
        // Fallback: watch-next panel parsing.
        return try await next(videoId: videoId)
    }

    /// Watch-next / up-next panel songs.
    func next(videoId: String, playlistId: String? = nil) async throws -> [Song] {
        var body = remixBody(["isRoot": true])
        body["videoId"] = videoId
        if let playlistId = playlistId { body["playlistId"] = playlistId }
        let json = try await post("next", body: body, client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnMusicWatchNextResultsRenderer",
                                "tabbedRenderer", "watchNextTabbedResultsRenderer", "tabs", 0,
                                "tabRenderer", "content", "musicQueueRenderer", "content", "playlistPanelRenderer")
        guard let panel = contents else { return [] }
        return Self.parsePanelSongs(panel)
    }

    /// music/get_queue — resolves full song metadata for a list of videoIds or a playlistId.
    func queue(videoIds: [String]? = nil, playlistId: String? = nil) async throws -> [Song] {
        var body = remixBody([:])
        if let videoIds = videoIds { body["videoIds"] = videoIds }
        if let playlistId = playlistId { body["playlistId"] = playlistId }
        let json = try await post("music/get_queue", body: body, client: YTClients.webRemix)
        var songs: [Song] = []
        if let queueDatas = JSON.asArray(JSON.dig(json, "queueDatas")) {
            for entry in queueDatas {
                if let renderer = JSON.dig(entry, "content", "playlistPanelVideoRenderer") {
                    if let song = Self.parsePanelVideoRenderer(renderer) {
                        songs.append(song)
                    }
                }
            }
        }
        return songs
    }

    // MARK: Browse pages

    func home() async throws -> [Shelf] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_home"]), client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
        return Self.parseShelfContents(contents)
    }

    /// A playlist or album page. Playlist ids start with VL/PL/RD/OL; album ids with MPRE/MPED.
    func playlistOrAlbum(browseId: String, isPlaylist: Bool) async throws -> MediaPage {
        let json = try await post("browse", body: remixBody(["browseId": browseId]), client: YTClients.webRemix)

        var title = ""
        var subtitle: String?
        var thumbnail: String?
        var radioPlaylistId: String?

        // Header — musicDetailHeaderRenderer (both albums and playlists).
        let header = JSON.dig(json, "header", "musicDetailHeaderRenderer")
        if let h = header {
            title = Self.runsText(JSON.dig(h, "title", "runs")) ?? ""
            subtitle = Self.runsText(JSON.dig(h, "subtitle", "runs"))
            thumbnail = Self.thumbnailUrl(JSON.dig(h, "thumbnail", "musicThumbnailRenderer", "thumbnail"))
            // "Play" radio playlist id from the header menu's top-level buttons.
            if let buttons = JSON.asArray(JSON.dig(h, "menu", "menuRenderer", "topLevelButtons")) {
                for button in buttons {
                    if let pl = JSON.asString(JSON.dig(button, "buttonRenderer", "navigationEndpoint", "watchPlaylistEndpoint", "playlistId")) {
                        radioPlaylistId = pl
                    }
                }
            }
        }

        // Songs shelf — musicPlaylistShelfRenderer (playlists) or musicShelfRenderer (albums).
        let tabs = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs") ?? JSON.dig(json, "contents", "twoColumnBrowseResultsRenderer", "tabs")
        let sectionContents = JSON.asArray(JSON.dig(tabs, 0, "tabRenderer", "content", "sectionListRenderer", "contents")) ?? []
        var songs: [Song] = []
        var continuation: String?
        for section in sectionContents {
            let shelfRenderer = JSON.dig(section, "musicPlaylistShelfRenderer") ?? JSON.dig(section, "musicShelfRenderer")
            guard let shelf = shelfRenderer else { continue }
            if let items = JSON.asArray(JSON.dig(shelf, "contents")) {
                for item in items {
                    if let renderer = JSON.dig(item, "musicResponsiveListItemRenderer"),
                       let song = Self.parseListItemSong(renderer) {
                        songs.append(song)
                    }
                }
            }
            continuation = Self.shelfContinuation(shelf) ?? continuation
            if title.isEmpty {
                title = Self.runsText(JSON.dig(shelf, "title", "runs")) ?? title
            }
        }
        if title.isEmpty {
            title = browseId
        }

        // Header-level fallback for playlists that only expose a title via header runs.
        if let h = header, title.isEmpty {
            title = Self.runsText(JSON.dig(h, "title", "runs")) ?? ""
        }

        return MediaPage(title: title, subtitle: subtitle, thumbnail: thumbnail,
                         songs: songs, continuation: continuation,
                         radioPlaylistId: radioPlaylistId, isPlaylist: isPlaylist, browseId: browseId)
    }

    /// Continuation for playlist/album song lists.
    func playlistContinuation(_ token: String, isPlaylist: Bool) async throws -> MediaPage {
        let json = try await post("browse", body: remixBody(["continuation": token]), client: YTClients.webRemix)
        let shelf = JSON.dig(json, "continuationContents", "musicPlaylistShelfContinuation") ?? JSON.dig(json, "continuationContents", "musicShelfContinuation")
        var songs: [Song] = []
        var nextToken: String?
        if let shelf = shelf {
            if let items = JSON.asArray(JSON.dig(shelf, "contents")) {
                for item in items {
                    if let renderer = JSON.dig(item, "musicResponsiveListItemRenderer"),
                       let song = Self.parseListItemSong(renderer) {
                        songs.append(song)
                    }
                }
            }
            nextToken = Self.shelfContinuation(shelf)
        }
        return MediaPage(title: "", subtitle: nil, thumbnail: nil, songs: songs,
                         continuation: nextToken, radioPlaylistId: nil, isPlaylist: isPlaylist, browseId: "")
    }

    func artist(browseId: String) async throws -> ArtistPage {
        let json = try await post("browse", body: remixBody(["browseId": browseId]), client: YTClients.webRemix)

        var name = ""
        var thumbnail: String?
        var radioPlaylistId: String?

        let immersive = JSON.dig(json, "header", "musicImmersiveHeaderRenderer")
        if let h = immersive {
            name = Self.runsText(JSON.dig(h, "title", "runs")) ?? ""
            thumbnail = Self.thumbnailUrl(JSON.dig(h, "thumbnail", "musicThumbnailRenderer", "thumbnail"))
            radioPlaylistId = JSON.asString(JSON.dig(h, "startRadioButton", "buttonRenderer", "navigationEndpoint", "watchPlaylistEndpoint", "playlistId"))
        } else {
            let detail = JSON.dig(json, "header", "musicDetailHeaderRenderer")
            if let h = detail {
                name = Self.runsText(JSON.dig(h, "title", "runs")) ?? ""
                thumbnail = Self.thumbnailUrl(JSON.dig(h, "thumbnail", "musicThumbnailRenderer", "thumbnail"))
            }
        }

        let contents = JSON.asArray(JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")) ?? []
        var songs: [Song] = []
        var shelves: [Shelf] = []
        for section in contents {
            if let shelf = JSON.dig(section, "musicShelfRenderer") {
                let sectionTitle = Self.runsText(JSON.dig(shelf, "title", "runs")) ?? "Songs"
                var sectionSongs: [Song] = []
                if let items = JSON.asArray(JSON.dig(shelf, "contents")) {
                    for item in items {
                        if let renderer = JSON.dig(item, "musicResponsiveListItemRenderer"),
                           let song = Self.parseListItemSong(renderer) {
                            sectionSongs.append(song)
                        }
                    }
                }
                if sectionSongs.isEmpty { continue }
                if songs.isEmpty && (sectionTitle.lowercased().contains("song") || sectionTitle.lowercased().contains("top")) {
                    songs = sectionSongs
                } else {
                    shelves.append(Shelf(title: sectionTitle, subtitle: nil, items: sectionSongs.map { .song($0) }))
                }
            } else if let shelf = JSON.dig(section, "musicCarouselShelfRenderer") {
                if let parsed = Self.parseCarouselShelf(shelf), !parsed.items.isEmpty {
                    shelves.append(parsed)
                }
            }
        }

        let artist = ArtistItem(browseId: browseId, name: name.isEmpty ? "Artist" : name, thumbnail: thumbnail, playCount: nil)
        return ArtistPage(artist: artist, songs: songs, shelves: shelves, radioPlaylistId: radioPlaylistId)
    }

    func explore() async throws -> [Shelf] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_explore"]), client: YTClients.webRemix)
        let contents = JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")
        return Self.parseShelfContents(contents)
    }

    /// Moods & genres categories (colored tiles in the Android app).
    func moodsAndGenres() async throws -> [MediaGridItem] {
        let json = try await post("browse", body: remixBody(["browseId": "FEmusic_moods_and_genres"]), client: YTClients.webRemix)
        var items: [MediaGridItem] = []
        let sections = JSON.asArray(JSON.dig(json, "contents", "singleColumnBrowseResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents")) ?? []
        for section in sections {
            guard let grid = JSON.dig(section, "gridRenderer") else { continue }
            if let gridItems = JSON.asArray(JSON.dig(grid, "items")) {
                for gi in gridItems {
                    if let two = JSON.dig(gi, "musicTwoRowItemRenderer") {
                        if let item = Self.parseTwoRowItem(two) {
                            items.append(item)
                        }
                    } else if let nav = JSON.dig(gi, "musicNavigationButtonRenderer") {
                        let text = JSON.asString(JSON.dig(nav, "buttonText"))
                        let bid = JSON.asString(JSON.dig(nav, "navigationEndpoint", "browseEndpoint", "browseId"))
                        if let text = text, let bid = bid {
                            items.append(.playlist(PlaylistItem(browseId: bid, title: text, owner: nil, countText: nil, thumbnail: nil, isLocal: false)))
                        }
                    }
                }
            }
        }
        return items
    }

    // MARK: - Shared parsers (static — pure functions)

    static func runsText(_ any: Any?) -> String? {
        guard let runs = JSON.asArray(any) else {
            return JSON.asString(any) // some fields are plain text
        }
        var out = ""
        for run in runs {
            if let t = JSON.asString(JSON.dig(run, "text")) { out += t }
        }
        return out.isEmpty ? nil : out
    }

    static func thumbnailUrl(_ any: Any?) -> String? {
        // `any` = thumbnail.thumbnails array
        guard let thumbs = JSON.asArray(any) else { return nil }
        // pick the largest
        var best: (url: String, size: Int)?
        for thumb in thumbs {
            if let url = JSON.asString(JSON.dig(thumb, "url")) {
                let w = JSON.asInt(JSON.dig(thumb, "width")) ?? 0
                if best == nil || w > best!.size {
                    best = (url, w)
                }
            }
        }
        return best?.url
    }

    /// "3:45" / "1:02:03" -> seconds
    static func parseDurationText(_ text: String?) -> Int? {
        guard let text = text, !text.isEmpty else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0]
    }

    // MARK: Song from musicResponsiveListItemRenderer

    static func parseListItemSong(_ renderer: Any) -> Song? {
        // videoId from playlistItemData or the title run's watch endpoint.
        var videoId = JSON.asString(JSON.dig(renderer, "playlistItemData", "videoId"))
        if videoId == nil {
            videoId = JSON.asString(JSON.dig(renderer, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text", "runs", 0, "navigationEndpoint", "watchEndpoint", "videoId"))
        }
        if videoId == nil {
            videoId = JSON.asString(JSON.dig(renderer, "navigationEndpoint", "watchEndpoint", "videoId"))
        }
        guard let vid = videoId, !vid.isEmpty else { return nil }

        let title = runsText(JSON.dig(renderer, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text", "runs")) ?? "Unknown"

        // Subtitle: runs joined then split on the " • " separator.
        let subtitleRuns = JSON.dig(renderer, "flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text", "runs")
        let subtitleText = runsText(subtitleRuns) ?? ""
        var artists: [String] = []
        var album: String?
        var duration: Int?
        let components = subtitleText.components(separatedBy: " • ").filter { !$0.isEmpty }
        if !components.isEmpty {
            let artistPart = components[0]
            artists = artistPart.components(separatedBy: ", ").filter { !$0.isEmpty }
            if components.count > 2 {
                album = components[1]
            }
            if let last = components.last, let d = parseDurationText(last) {
                duration = d
            }
        }

        let thumb = thumbnailUrl(JSON.dig(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail"))
        return Song(videoId: vid, title: title, artists: artists, album: album,
                    duration: duration, thumbnail: thumb,
                    isLocal: false, localKey: nil, isDemo: false)
    }

    // MARK: MediaGridItem from musicTwoRowItemRenderer

    static func parseTwoRowItem(_ renderer: Any) -> MediaGridItem? {
        let title = runsText(JSON.dig(renderer, "title", "runs")) ?? JSON.asString(JSON.dig(renderer, "title", "text"))
        guard let title = title, !title.isEmpty else { return nil }
        let subtitle = runsText(JSON.dig(renderer, "subtitle", "runs")) ?? JSON.asString(JSON.dig(renderer, "subtitle", "text"))
        let thumb = thumbnailUrl(JSON.dig(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail"))

        // Watch endpoint -> song/video
        if let vid = JSON.asString(JSON.dig(renderer, "navigationEndpoint", "watchEndpoint", "videoId")) {
            var artists: [String] = []
            var album: String?
            var duration: Int?
            let comps = (subtitle ?? "").components(separatedBy: " • ").filter { !$0.isEmpty }
            if !comps.isEmpty {
                artists = comps[0].components(separatedBy: ", ")
                if comps.count > 2 { album = comps[1] }
                duration = parseDurationText(comps.last)
            }
            return .song(Song(videoId: vid, title: title, artists: artists, album: album,
                              duration: duration, thumbnail: thumb,
                              isLocal: false, localKey: nil, isDemo: false))
        }

        // Browse endpoint -> artist / album / playlist
        let browseId = JSON.asString(JSON.dig(renderer, "navigationEndpoint", "browseEndpoint", "browseId")) ?? ""
        let pageType = JSON.asString(JSON.dig(renderer, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicPage", "musicPageType")) ?? ""
        return classifyBrowse(browseId: browseId, pageType: pageType, title: title, subtitle: subtitle, thumbnail: thumb)
    }

    static func classifyBrowse(browseId: String, pageType: String, title: String, subtitle: String?, thumbnail: String?) -> MediaGridItem? {
        if browseId.isEmpty { return nil }
        let comps = (subtitle ?? "").components(separatedBy: " • ").filter { !$0.isEmpty }
        if pageType.contains("ARTIST") || browseId.hasPrefix("UC") {
            return .artist(ArtistItem(browseId: browseId, name: title, thumbnail: thumbnail, playCount: nil))
        }
        if pageType.contains("ALBUM") || browseId.hasPrefix("MPRE") || browseId.hasPrefix("MPED") || browseId.hasPrefix("MPSP") {
            let artists = comps.first?.components(separatedBy: ", ") ?? []
            let year = comps.count > 1 ? comps[1] : nil
            return .album(AlbumItem(browseId: browseId, title: title, artists: artists, year: year, thumbnail: thumbnail, isSingle: false))
        }
        // VL/PL/RD/OL -> playlist
        let owner = comps.first
        let countText = comps.count > 1 ? comps[1] : nil
        return .playlist(PlaylistItem(browseId: browseId, title: title, owner: owner, countText: countText, thumbnail: thumbnail, isLocal: false))
    }

    // MARK: musicResponsiveListItemRenderer -> generic MediaGridItem (search lists, shelves)

    static func parseListItem(_ renderer: Any) -> MediaGridItem? {
        // Song?
        if let song = parseListItemSong(renderer) {
            // If the item navigates to a browse page, prefer the browse classification.
            let titleRunBrowse = JSON.asString(JSON.dig(renderer, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text", "runs", 0, "navigationEndpoint", "browseEndpoint", "browseId"))
            if let bid = titleRunBrowse, !bid.isEmpty {
                let title = song.title
                let subtitle = song.artistsText.isEmpty ? nil : song.artistsText
                if let item = classifyBrowse(browseId: bid, pageType: "", title: title, subtitle: subtitle, thumbnail: song.thumbnail) {
                    return item
                }
            }
            return .song(song)
        }
        // Pure browse item (artist row without playlistItemData).
        let title = runsText(JSON.dig(renderer, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text", "runs")) ?? ""
        let subtitle = runsText(JSON.dig(renderer, "flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"))
        var browseId = JSON.asString(JSON.dig(renderer, "navigationEndpoint", "browseEndpoint", "browseId")) ?? ""
        if browseId.isEmpty {
            browseId = JSON.asString(JSON.dig(renderer, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text", "runs", 0, "navigationEndpoint", "browseEndpoint", "browseId")) ?? ""
        }
        if browseId.isEmpty { return nil }
        let thumb = thumbnailUrl(JSON.dig(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail"))
        return classifyBrowse(browseId: browseId, pageType: "", title: title, subtitle: subtitle, thumbnail: thumb)
    }

    // MARK: Watch-next panel

    static func parsePanelSongs(_ panel: Any) -> [Song] {
        var songs: [Song] = []
        if let contents = JSON.asArray(JSON.dig(panel, "contents")) {
            for item in contents {
                if let renderer = JSON.dig(item, "playlistPanelVideoRenderer"),
                   let song = parsePanelVideoRenderer(renderer) {
                    songs.append(song)
                }
            }
        }
        return songs
    }

    static func parsePanelVideoRenderer(_ renderer: Any) -> Song? {
        let vid = JSON.asString(JSON.dig(renderer, "videoId")) ?? ""
        guard !vid.isEmpty else { return nil }
        let title = runsText(JSON.dig(renderer, "title", "runs")) ?? "Unknown"
        let artists = (runsText(JSON.dig(renderer, "shortBylineText", "runs")) ?? "").components(separatedBy: " • ").filter { !$0.isEmpty }
        let duration = parseDurationText(runsText(JSON.dig(renderer, "lengthText", "runs")) ?? JSON.asString(JSON.dig(renderer, "lengthText", "simpleText")))
        let thumb = thumbnailUrl(JSON.dig(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnails"))
            ?? thumbnailUrl(JSON.dig(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail"))
        return Song(videoId: vid, title: title, artists: artists, album: nil,
                    duration: duration, thumbnail: thumb,
                    isLocal: false, localKey: nil, isDemo: false)
    }

    // MARK: Shelves (home / explore / artist carousels)

    static func parseShelfContents(_ contents: Any?) -> [Shelf] {
        var shelves: [Shelf] = []
        guard let sections = JSON.asArray(contents) else { return shelves }
        for section in sections {
            if let shelf = JSON.dig(section, "musicCarouselShelfRenderer") {
                if let parsed = parseCarouselShelf(shelf) {
                    shelves.append(parsed)
                }
            } else if let shelf = JSON.dig(section, "musicShelfRenderer") {
                let title = runsText(JSON.dig(shelf, "title", "runs")) ?? "Songs"
                var items: [MediaGridItem] = []
                if let list = JSON.asArray(JSON.dig(shelf, "contents")) {
                    for item in list {
                        if let renderer = JSON.dig(item, "musicResponsiveListItemRenderer"),
                           let gridItem = parseListItem(renderer) {
                            items.append(gridItem)
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

    static func parseCarouselShelf(_ shelf: Any) -> Shelf? {
        let title = runsText(JSON.dig(shelf, "header", "musicCarouselShelfBasicHeaderRenderer", "title", "runs")) ?? ""
        var items: [MediaGridItem] = []
        if let contents = JSON.asArray(JSON.dig(shelf, "contents")) {
            for content in contents {
                if let two = JSON.dig(content, "musicTwoRowItemRenderer") {
                    if let item = parseTwoRowItem(two) {
                        items.append(item)
                    }
                } else if let list = JSON.dig(content, "musicResponsiveListItemRenderer") {
                    if let item = parseListItem(list) {
                        items.append(item)
                    }
                }
            }
        }
        if title.isEmpty && items.isEmpty { return nil }
        return Shelf(title: title.isEmpty ? "Browse" : title, subtitle: nil, items: items)
    }

    static func shelfContinuation(_ shelf: Any) -> String? {
        if let conts = JSON.asArray(JSON.dig(shelf, "continuations")) {
            for cont in conts {
                if let token = JSON.asString(JSON.dig(cont, "nextContinuationData", "continuation")) {
                    return token
                }
                if let token = JSON.asString(JSON.dig(cont, "reloadContinuationData", "continuation")) {
                    return token
                }
            }
        }
        return nil
    }

    // MARK: Search parsing

    func parseSearch(_ json: Any) throws -> SearchResult {
        var items: [MediaGridItem] = []
        var songs: [Song] = []
        var continuation: String?

        // Main search response: contents.tabbedSearchResultsRenderer...
        var sections = JSON.asArray(JSON.dig(json, "contents", "tabbedSearchResultsRenderer", "tabs", 0, "tabRenderer", "content", "sectionListRenderer", "contents"))
        // Continuation response: continuationContents.musicShelfRenderer / sectionListContinuation
        if sections == nil {
            let contShelf = JSON.dig(json, "continuationContents", "musicShelfRenderer")
            if let shelf = contShelf {
                sections = [shelf]
            } else {
                sections = JSON.asArray(JSON.dig(json, "continuationContents", "sectionListContinuation", "contents"))
            }
        }
        guard let sections = sections else { throw InnerTubeError.badResponse }

        for section in sections {
            if let shelf = JSON.dig(section, "musicShelfRenderer") {
                if let list = JSON.asArray(JSON.dig(shelf, "contents")) {
                    for item in list {
                        guard let renderer = JSON.dig(item, "musicResponsiveListItemRenderer") else { continue }
                        if let gridItem = Self.parseListItem(renderer) {
                            items.append(gridItem)
                            if case .song(let s) = gridItem { songs.append(s) }
                        }
                    }
                }
                continuation = Self.shelfContinuation(shelf) ?? continuation
            } else if let shelf = JSON.dig(section, "musicCardShelfRenderer") {
                // Top result card — parse the embedded list item.
                if let renderer = JSON.dig(shelf, "contents") {
                    if let gridItem = Self.parseListItem(renderer) {
                        items.append(gridItem)
                        if case .song(let s) = gridItem { songs.append(s) }
                    }
                }
            } else if let grid = JSON.dig(section, "gridRenderer") {
                if let list = JSON.asArray(JSON.dig(grid, "items")) {
                    for item in list {
                        if let two = JSON.dig(item, "musicTwoRowItemRenderer") {
                            if let gridItem = Self.parseTwoRowItem(two) {
                                items.append(gridItem)
                                if case .song(let s) = gridItem { songs.append(s) }
                            }
                        }
                    }
                }
            }
        }

        if items.isEmpty && continuation == nil {
            throw InnerTubeError.badResponse
        }
        return SearchResult(items: items, songs: songs, continuation: continuation)
    }
}
