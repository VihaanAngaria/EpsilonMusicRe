import Foundation
import CryptoKit

// MARK: - Spotify import (spotify/ + spotifyimport/ parity)

/// The Swift port of the Android app's Spotify web-player internal stack:
/// sp_dc cookie → TOTP-signed /api/token → api-partner pathfinder GraphQL
/// persisted queries → track matching against YouTube Music.
@MainActor
final class SpotifyImporter: ObservableObject {

    static let shared = SpotifyImporter()

    // MARK: Persisted session

    var spDc: String {
        get { UserDefaults.standard.string(forKey: "spotify_sp_dc") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "spotify_sp_dc") }
    }
    var spKey: String {
        get { UserDefaults.standard.string(forKey: "spotify_sp_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "spotify_sp_key") }
    }
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "spotify_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "spotify_access_token") }
    }
    private var tokenExpiresAt: Double {
        get { UserDefaults.standard.object(forKey: "spotify_access_token_expires_at") as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: "spotify_access_token_expires_at") }
    }
    var accountName: String {
        get { UserDefaults.standard.string(forKey: "spotify_account_name") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "spotify_account_name") }
    }

    var isSignedIn: Bool { !spDc.isEmpty }

    // MARK: Progress

    enum ImportPhase: Equatable {
        case idle
        case signingIn
        case loading
        case matching(index: Int, total: Int, query: String)
        case done(imported: Int, failed: Int)
        case error(String)
    }

    @Published var phase: ImportPhase = .idle
    @Published var sources: [SpotifySource] = []

    private init() {}

    // MARK: Token (SpotifyAuth.fetchAccessToken parity)

    private struct TOTPSecret: Codable {
        var s: String
        var v: Int
    }

    func fetchAccessToken() async throws -> String {
        if let token = accessToken, Date().timeIntervalSince1970 < tokenExpiresAt - 60 {
            return token
        }
        // 1. TOTP secret from the public gist.
        let gistUrl = "https://gist.githubusercontent.com/sonic-liberation/22ed9c6ba463899e933427f7de1f0eef/raw/"
        var secret = ""
        var version = 1
        if let (_, json) = await LyricsHTTP.get(url: gistUrl, timeout: 15),
           let entries = JSON.asArray(json) {
            for entry in entries {
                if let s = JSON.asString(entry["s"]), let v = JSON.asInt(entry["v"]), v >= version {
                    secret = s
                    version = v
                }
            }
        }
        guard !secret.isEmpty else { throw SpotifyError.tokenFailed }

        // 2. Server time.
        var serverTime = Int(Date().timeIntervalSince1970)
        if let (_, timeJson) = await LyricsHTTP.get(url: "https://open.spotify.com/api/server-time", timeout: 10) {
            if let t = JSON.asInt(timeJson["serverTime"]) { serverTime = t }
        }

        // 3. TOTP (RFC 6238, HMAC-SHA1, 6 digits, 30 s step).
        let totp = Self.totp(secret: secret, timestamp: serverTime)

        // 4. Token exchange with the sp_dc cookie.
        var cookieHeader = "sp_dc=\(spDc)"
        if !spKey.isEmpty { cookieHeader += "; sp_key=\(spKey)" }
        let url = "https://open.spotify.com/api/token?reason=transport&productType=web-player&totp=\(totp)&totpServer=\(totp)&totpVer=\(version)"
        guard let request = LyricsHTTP.buildRequest(url: url, method: "GET",
                                                    headers: ["Cookie": cookieHeader], body: nil, timeout: 20) else {
            throw SpotifyError.tokenFailed
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = JSON.parse(data) else {
            throw SpotifyError.invalidCookie
        }
        let isAnonymous = JSON.asBool(json["isAnonymous"]) ?? true
        if isAnonymous {
            throw SpotifyError.invalidCookie
        }
        guard let token = JSON.asString(json["accessToken"]) else { throw SpotifyError.tokenFailed }
        let expiresIn = JSON.asInt(json["accessTokenExpirationTimestampMs"]).map { Double($0) / 1000.0 } ?? 3600.0
        accessToken = token
        tokenExpiresAt = Date().timeIntervalSince1970 + expiresIn
        if let name = JSON.asString(JSON.dig(json, "info", "name")) {
            accountName = name
        }
        return token
    }

    // MARK: TOTP

    static func totp(secret: String, timestamp: Int) -> String {
        let counter = UInt64(timestamp / 30)
        let key = base32Decode(secret)
        var counterBytes = [UInt8](repeating: 0, count: 8)
        var value = counter
        for i in (0..<8).reversed() {
            counterBytes[i] = UInt8(value & 0xFF)
            value >>= 8
        }
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(counterBytes), using: SymmetricKey(data: Data(key)))
        var digest = [UInt8](hmac)
        let offset = Int(digest[19] & 0x0F)
        var code = (UInt32(digest[offset]) & 0x7F) << 24
        code |= UInt32(digest[offset + 1]) << 16
        code |= UInt32(digest[offset + 2]) << 8
        code |= UInt32(digest[offset + 3])
        return String(format: "%06d", code % 1_000_000)
    }

    static func base32Decode(_ input: String) -> [UInt8] {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var value = 0
        var output: [UInt8] = []
        for ch in input.uppercased() {
            guard let idx = alphabet.firstIndex(of: ch) else { continue }
            let digit = alphabet.distance(from: alphabet.startIndex, to: idx)
            value = (value << 5) | digit
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return output
    }

    // MARK: GraphQL (Spotify.kt parity — persisted queries)

    enum GqlOperation: String {
        case profileAttributes, libraryV3, fetchPlaylist, fetchLibraryTracks
        case searchDesktop, getAlbum, home
    }

    static let gqlHashes: [String: String] = [
        "profileAttributes": "53bcb064f6cd18c23f752bc324a791194d20df612d8e1239c735144ab0399ced",
        "libraryV3": "973e511ca44261fda7eebac8b653155e7caee3675abb4fb110cc1b8c78b091c3",
        "fetchPlaylist": "346811f856fb0b7e4f6c59f8ebea78dd081c6e2fb01b77c954b26259d5fc6763",
        "fetchLibraryTracks": "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",
        "searchDesktop": "4801118d4a100f756e833d33984436a3899cff359c532f8fd3aaf174b60b3b49",
        "queryArtistOverview": "5b9e64f43843fa3a9b6a98543600299b0a2cbbbccfdcdcef2402eb9c1017ca4c",
        "getAlbum": "b9bfabef66ed756e5e13f68a942deb60bd4125ec1f1be8cc42769dc0259b4b10",
        "queryWhatsNewFeed": "3b53dede3c6054e8b7c962dd280eb6761c5d1c82b06b039f4110d76a62b4966b",
        "addToPlaylist": "47b2a1234b17748d332dd0431534f22450e9ecbb3d5ddcdacbd83368636a0990",
        "editPlaylistAttributes": "35a1a9ce3a2f4f8c32ee0e24c63c2069c6613c0a0b7e56d0e40dabe69a0b4f80",
        "addToLibrary": "7c5a69420e2bfae3da5cc4e14cbc8bb3f6090f80afc00ffc179177f19be3f33d",
        "home": "23e37f2e58d82d567f27080101d36609009d8c3676457b1086cb0acc55b72a5d",
    ]

    private func gql(_ operation: GqlOperation, variables: [String: Any]) async throws -> Any {
        let token = try await fetchAccessToken()
        let hash = Self.gqlHashes[operation.rawValue] ?? ""
        let body: [String: Any] = [
            "variables": variables,
            "operationName": operation.rawValue,
            "extensions": [
                "persistedQuery": ["version": 1, "sha256Hash": hash],
            ] as [String: Any],
        ]
        guard let request = LyricsHTTP.buildRequest(url: "https://api-partner.spotify.com/pathfinder/v2/query",
                                                    method: "POST",
                                                    headers: [
                                                        "Authorization": "Bearer \(token)",
                                                        "app-platform": "WebPlayer",
                                                        "Content-Type": "application/json",
                                                        "Origin": "https://open.spotify.com",
                                                        "Referer": "https://open.spotify.com",
                                                    ],
                                                    body: try? JSONSerialization.data(withJSONObject: body), timeout: 20) else {
            throw SpotifyError.requestFailed
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.requestFailed }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyError.requestFailed
        }
        guard let json = JSON.parse(data) else { throw SpotifyError.requestFailed }
        return json
    }

    // MARK: Sources & tracks

    struct SpotifySource: Identifiable, Equatable {
        var id: String
        var name: String
        var isLikedSongs: Bool
        var trackCount: Int

        static func == (lhs: SpotifySource, rhs: SpotifySource) -> Bool { lhs.id == rhs.id }
    }

    struct SpotifyTrack {
        var title: String
        var artist: String
        var durationMs: Int
    }

    func loadSources() async {
        phase = .loading
        do {
            let token = try await fetchAccessToken()
            _ = token
            var out: [SpotifySource] = []
            // Liked songs pseudo-source.
            out.append(SpotifySource(id: "SPOTIFY_LIKED", name: "Liked Songs", isLikedSongs: true, trackCount: 0))
            // libraryV3 playlists.
            let json = try await gql(.libraryV3, variables: [
                "filters": ["Playlists"],
                "order": NSNull(),
                "textFilter": "",
                "features": ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "EVENTS"],
                "limit": 50,
                "offset": 0,
                "flatten": true,
                "expandedFolders": [],
                "folderUri": NSNull(),
                "includeFoldersWhenFlattening": false,
            ])
            var cursor = json
            for _ in 0..<10 {
                let items = JSON.asArray(JSON.dig(cursor, "data", "me", "libraryV3", "items"))
                if let items = items {
                    for item in items {
                        let content = JSON.dig(item, "data", "playlistV2")
                        let uri = JSON.asString(JSON.dig(content, "uri")) ?? ""
                        let name = JSON.asString(JSON.dig(content, "name")) ?? "Playlist"
                        let count = JSON.asInt(JSON.dig(content, "trackCount", "totalCount")) ?? 0
                        if let playlistId = uri.components(separatedBy: ":").last, !playlistId.isEmpty, !uri.contains("liked") {
                            out.append(SpotifySource(id: playlistId, name: name, isLikedSongs: false, trackCount: count))
                        }
                    }
                }
                let nextOffset = JSON.asInt(JSON.dig(cursor, "data", "me", "libraryV3", "offset"))
                let total = JSON.asInt(JSON.dig(cursor, "data", "me", "libraryV3", "totalCount")) ?? 0
                let loaded = (nextOffset ?? 0) + (items?.count ?? 0)
                if loaded == 0 || loaded >= total { break }
                // Follow pagination through a second call.
                cursor = try await gql(.libraryV3, variables: [
                    "filters": ["Playlists"],
                    "order": NSNull(),
                    "textFilter": "",
                    "features": ["LIKED_SONGS", "YOUR_EPISODES_V2", "PRERELEASES", "EVENTS"],
                    "limit": 50,
                    "offset": loaded,
                    "flatten": true,
                    "expandedFolders": [],
                    "folderUri": NSNull(),
                    "includeFoldersWhenFlattening": false,
                ])
            }
            sources = out
            phase = .idle
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Fetches tracks for a source (fetchPlaylist / fetchLibraryTracks).
    func loadTracks(source: SpotifySource) async throws -> [SpotifyTrack] {
        var all: [SpotifyTrack] = []
        if source.isLikedSongs {
            var offset = 0
            while true {
                let json = try await gql(.fetchLibraryTracks, variables: ["offset": offset, "limit": 100])
                let edges = JSON.asArray(JSON.dig(json, "data", "me", "libraryV3", "items")) ?? []
                if edges.isEmpty { break }
                for edge in edges {
                    if let track = parseTrackItem(edge) { all.append(track) }
                }
                if edges.count < 100 { break }
                offset += 100
            }
        } else {
            var offset = 0
            while true {
                let json = try await gql(.fetchPlaylist, variables: [
                    "uri": "spotify:playlist:\(source.id)",
                    "offset": offset,
                    "limit": 50,
                    "enableWatchFeedEntrypoint": false,
                ])
                let edges = JSON.asArray(JSON.dig(json, "data", "playlistV2", "content", "items")) ?? []
                if edges.isEmpty { break }
                for edge in edges {
                    if let track = parseTrackItem(edge) { all.append(track) }
                }
                if edges.count < 50 { break }
                offset += 50
            }
        }
        return all
    }

    private func parseTrackItem(_ edge: Any) -> SpotifyTrack? {
        var content = JSON.dig(edge, "track") ?? JSON.dig(edge, "content") ?? edge
        if let wrapper = content as? [String: Any], let inner = wrapper["data"] as? [String: Any] {
            // {data: {track: {...}}} nesting
            if let track = inner["track"] as? [String: Any] {
                content = track
            } else if let trackDict = inner as? [String: Any] {
                content = trackDict
            }
        }
        let title = JSON.asString(JSON.dig(content, "name")) ?? ""
        guard !title.isEmpty else { return nil }
        var artist = ""
        if let artists = JSON.asArray(JSON.dig(content, "artists")) {
            artist = artists.compactMap { JSON.asString(JSON.dig($0, "name")) }.joined(separator: ", ")
        }
        let durationMs = JSON.asInt(JSON.dig(content, "duration", "totalMilliseconds")) ?? 0
        return SpotifyTrack(title: title, artist: artist, durationMs: durationMs)
    }

    // MARK: Matching + import (SpotifyMapper + SpotifyImportRepository parity)

    /// Match score: bigram similarity of title (0.45) + artist (0.35) + duration (0.20).
    static func matchScore(query: SpotifyTrack, candidate: Song) -> Double {
        let titleScore = Self.bigramSimilarity(Self.normalized(query.title), Self.normalized(candidate.title))
        let artistScore = Self.bigramSimilarity(Self.normalized(query.artist), Self.normalized(candidate.artistsText))
        var durationScore = 0.0
        if query.durationMs > 0, let duration = candidate.duration, duration > 0 {
            let diff = abs(Double(query.durationMs) / 1000.0 - Double(duration))
            if diff <= 2 { durationScore = 1.0 } else if diff <= 5 { durationScore = 0.8 }
            else if diff <= 10 { durationScore = 0.5 } else if diff <= 30 { durationScore = 0.2 }
        }
        return titleScore * 0.45 + artistScore * 0.35 + durationScore * 0.20
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func bigramSimilarity(_ a: String, _ b: String) -> Double {
        let first = Self.normalized(a)
        let second = Self.normalized(b)
        guard first.count > 1, second.count > 1 else {
            return first == second ? 1.0 : 0.0
        }
        let firstGrams = Set((0..<(first.count - 1)).map { String(Array(first)[$0...($0 + 1)]) })
        let secondGrams = Set((0..<(second.count - 1)).map { String(Array(second)[$0...($0 + 1)]) })
        let intersection = firstGrams.intersection(secondGrams).count
        let union = firstGrams.union(secondGrams).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    /// Imports one source into the local library as a playlist, matching on YouTube Music.
    func importSource(source: SpotifySource) async {
        do {
            let tracks = try await loadTracks(source: source)
            guard !tracks.isEmpty else {
                phase = .done(imported: 0, failed: 0)
                return
            }
            var matched: [Song] = []
            var failed = 0
            for (index, track) in tracks.enumerated() {
                phase = .matching(index: index + 1, total: tracks.count, query: "\(track.artist) \(track.title)")
                let query = "\(Self.primaryArtist(track.artist)) \(track.title)"
                if let result = try? await InnerTube.shared.search(query: query, filter: .songs),
                   let best = Self.bestMatch(for: track, in: result.songs) {
                    matched.append(best)
                } else {
                    failed += 1
                }
            }
            if !matched.isEmpty {
                let name = source.isLikedSongs ? "Spotify Liked Songs" : source.name
                _ = LibraryStore.shared.createPlaylist(named: name, songs: matched)
            }
            phase = .done(imported: matched.count, failed: failed)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    static func primaryArtist(_ artist: String) -> String {
        for separator in [", ", " & ", " feat. ", " feat "] {
            if let range = artist.range(of: separator) {
                return String(artist[artist.startIndex..<range.lowerBound])
            }
        }
        return artist
    }

    static func bestMatch(for track: SpotifyTrack, in songs: [Song]) -> Song? {
        var best: (score: Double, song: Song)?
        for song in songs.prefix(5) {
            let score = matchScore(query: track, candidate: song)
            if score > (best?.score ?? 0.3) {
                best = (score, song)
            }
        }
        return best?.song
    }

    /// Playlist link/URI parser (`spotify:playlist:ID`, `open.spotify.com/playlist/ID`, bare ID).
    static func extractPlaylistId(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "playlist/") {
            let tail = String(trimmed[range.upperBound...])
            return tail.components(separatedBy: CharacterSet(charactersIn: "?/")).first
        }
        if let range = trimmed.range(of: "spotify:playlist:") {
            return String(trimmed[range.upperBound...])
        }
        if trimmed.range(of: "^[A-Za-z0-9]{16,}$", options: .regularExpression) != nil {
            return trimmed
        }
        return nil
    }

    // MARK: Import from a public playlist link (no login needed for the token,
    // but the web token requires sp_dc — matching the Android behavior).

    func importFromLink(_ link: String) async {
        guard let id = Self.extractPlaylistId(from: link) else {
            phase = .error("Couldn't read a playlist id from that link.")
            return
        }
        let source = SpotifySource(id: id, name: "Spotify playlist", isLikedSongs: false, trackCount: 0)
        await importSource(source: source)
    }

    // MARK: Sign-out

    func signOut() {
        spDc = ""
        spKey = ""
        accessToken = nil
        tokenExpiresAt = 0
        accountName = ""
        sources = []
        phase = .idle
    }

    enum SpotifyError: LocalizedError {
        case tokenFailed, invalidCookie, requestFailed

        var errorDescription: String? {
            switch self {
            case .tokenFailed: return "Couldn't get a Spotify web token"
            case .invalidCookie: return "The sp_dc cookie is invalid or expired — sign in again"
            case .requestFailed: return "Spotify request failed"
            }
        }
    }
}
