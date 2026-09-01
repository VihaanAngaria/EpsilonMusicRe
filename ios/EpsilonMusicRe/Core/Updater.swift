import Foundation

// MARK: - Updater (epsilonmusic/updater parity — GitHub releases)

@MainActor
final class Updater: ObservableObject {

    static let shared = Updater()

    struct UpdateInfo {
        var version: String
        var downloadUrl: String?
        var downloadSize: Int?
        var changelog: [(title: String, items: [String])]
        var imageUrl: String?
        var body: String
    }

    @Published var updateInfo: UpdateInfo?
    @Published var isChecking = false
    @Published var lastError: String?

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdateCheck") }
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    private init() {}

    func checkForUpdates() async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        guard let url = URL(string: "https://api.github.com/repos/VihaanAngaria/EpsilonMusicRe/releases/latest") else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = JSON.parse(data), let json = parsed as? [String: Any] else {
            lastError = "Couldn't reach GitHub for the latest release."
            return
        }
        let tag = JSON.asString(json["tag_name"]) ?? ""
        guard Self.isNewer(current: currentVersion, latest: tag) else {
            updateInfo = nil
            return
        }
        var downloadUrl: String?
        var downloadSize: Int?
        for asset in JSON.asArray(json["assets"]) ?? [] {
            guard let assetDict = asset as? [String: Any] else { continue }
            let name = JSON.asString(assetDict["name"]) ?? ""
            if name.lowercased().hasSuffix(".ipa") || name.lowercased().hasSuffix(".zip") || name.lowercased().contains("ios") {
                downloadUrl = JSON.asString(assetDict["browser_download_url"])
                downloadSize = JSON.asInt(assetDict["size"])
                break
            }
        }
        if downloadUrl == nil {
            downloadUrl = JSON.asString(json["html_url"])
        }
        let body = JSON.asString(json["body"]) ?? ""
        var changelog: [(String, [String])] = []
        var imageUrl: String?
        // changelog.json asset (Android format).
        if let changelogAsset = (JSON.asArray(json["assets"]) ?? []).compactMap({ $0 as? [String: Any] }).first(where: { JSON.asString($0["name"]) == "changelog.json" }),
           let changelogUrl = JSON.asString(changelogAsset["browser_download_url"]) {
            if let (_, cjParsed) = await LyricsHTTP.get(url: changelogUrl, timeout: 15),
               let cj = cjParsed as? [String: Any] {
                imageUrl = JSON.asString(cj["image"])
                if let sections = JSON.asArray(cj["changelog"]) {
                    for section in sections {
                        guard let sectionDict = section as? [String: Any] else { continue }
                        let title = JSON.asString(sectionDict["title"]) ?? ""
                        let items = (JSON.asArray(sectionDict["items"]) ?? []).compactMap { JSON.asString($0) }
                        changelog.append((title, items))
                    }
                }
            }
        }
        if changelog.isEmpty && !body.isEmpty {
            // Markdown fallback: split "## " sections.
            for rawSection in body.components(separatedBy: "\n## ") {
                let lines = rawSection.components(separatedBy: "\n").filter { !$0.isEmpty }
                guard let first = lines.first else { continue }
                let items = lines.dropFirst().map { $0.replacingOccurrences(of: "- ", with: "").trimmingCharacters(in: .whitespaces) }
                changelog.append((first.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces), items.filter { !$0.isEmpty }))
            }
            // Extract image.
            if let regex = try? NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\((https?[^\\)]+)\\)") {
                let ns = body as NSString
                if let match = regex.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
                   Range(match.range(at: 1), in: body) != nil,
                   let r = Range(match.range(at: 1), in: body) {
                    imageUrl = String(body[r])
                }
            }
        }
        updateInfo = UpdateInfo(version: tag, downloadUrl: downloadUrl, downloadSize: downloadSize,
                                changelog: changelog, imageUrl: imageUrl, body: body)
    }

    /// Android's isNewerVersion (strips v/b prefixes; beta sorts below stable).
    static func isNewer(current: String, latest: String) -> Bool {
        func clean(_ v: String) -> String {
            var s = v.lowercased()
            if s.hasPrefix("v") { s.removeFirst() }
            if s.hasPrefix("b") { s.removeFirst() }
            return s
        }
        let c = clean(current)
        let l = clean(latest)
        guard !l.isEmpty, l != c else { return false }
        let cParts = c.split(separator: ".").compactMap { Int($0) }
        let lParts = l.split(separator: ".").compactMap { Int($0) }
        let count = max(cParts.count, lParts.count)
        for i in 0..<count {
            let a = i < cParts.count ? cParts[i] : 0
            let b = i < lParts.count ? lParts[i] : 0
            if b > a { return true }
            if b < a { return false }
        }
        return false
    }
}

// MARK: - Backup & restore (JSON export/import)

@MainActor
final class BackupRestore {

    struct BackupFile: Codable {
        var version: Int = 1
        var exportedAt: Double
        var settings: [String: String]
        var likedSongs: [Song]
        var history: [HistoryEntry]
        var playlists: [LocalPlaylist]
        var downloadedIds: [String]
        var recognitionHistory: [RecognitionResult]
    }

    static var defaultBackupUrl: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("epsilonmusic-backup.json")
    }

    /// Exports settings + library to a JSON backup (the Android app zips DataStore + Room).
    static func export() -> URL? {
        var settings: [String: String] = [:]
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("yt_") || key.hasPrefix("lt_") || key.hasPrefix("lyrics") || key.hasPrefix("discord_") || key.hasPrefix("spotify_") || key.hasPrefix("listenbrainz_") || key.hasPrefix("lastfm") || key.hasPrefix("openRouter") || key.hasPrefix("deepl") || key == "aiProvider" || key == "translateMode" || key == "translateLanguage" || key == "themeMode" || key == "pureBlack" || key == "dynamicTheme" || key == "accentHex" {
            settings[key] = "\(defaults.object(forKey: key) ?? "")"
        }
        let backup = BackupFile(
            exportedAt: Date().timeIntervalSince1970,
            settings: settings,
            likedSongs: LibraryStore.shared.likedSongs,
            history: LibraryStore.shared.history,
            playlists: LibraryStore.shared.playlists,
            downloadedIds: DownloadManager.shared.downloadedSongs().map(\.id),
            recognitionHistory: RecognitionManager.shared.history)
        guard let data = try? JSONEncoder().encode(backup) else { return nil }
        do {
            try data.write(to: defaultBackupUrl, options: .atomic)
            return defaultBackupUrl
        } catch {
            return nil
        }
    }

    /// Restores a backup file.
    static func restore(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(BackupFile.self, from: data) else { return false }
        let library = LibraryStore.shared
        library.restore(liked: backup.likedSongs, history: backup.history, playlists: backup.playlists)
        for (key, value) in backup.settings {
            UserDefaults.standard.set(value, forKey: key)
        }
        RecognitionManager.shared.history = backup.recognitionHistory
        return true
    }
}

// MARK: - Canvas artwork (canvas/ + applecanvas/ + epsilonmusiccanvas/ parity)

enum CanvasProvider {

    struct CanvasArtwork: Equatable {
        var animatedUrl: String?
        var videoUrl: String?
        var staticUrl: String?
    }

    /// Community manifest provider (epsilonmusic.ct.ws/canvas.json, 60 s TTL).
    static func epsilonMusicCanvas(title: String, artist: String) async -> CanvasArtwork? {
        guard let data = await fetchManifest(), let json = JSON.parse(data),
              let items = JSON.asArray(JSON.dig(json, "items")) else { return nil }
        let normalizedTitle = normalize(title)
        let normalizedArtist = normalize(artist)
        for rawItem in items {
            guard let item = rawItem as? [String: Any] else { continue }
            let song = normalize(JSON.asString(item["song"]) ?? "")
            let songArtist = normalize(JSON.asString(item["artist"]) ?? "")
            let url = JSON.asString(item["url"])
            guard let url = url, !url.isEmpty else { continue }
            let titleMatch = song.contains(normalizedTitle) || normalizedTitle.contains(song)
            let artistMatch = songArtist.contains(normalizedArtist) || normalizedArtist.contains(songArtist)
            if titleMatch && (artistMatch || songArtist.isEmpty) {
                return CanvasArtwork(animatedUrl: nil, videoUrl: url, staticUrl: nil)
            }
        }
        return nil
    }

    private static var manifestData: Data?
    private static var manifestFetchedAt: Date?

    private static func fetchManifest() async -> Data? {
        if let data = manifestData, let fetched = manifestFetchedAt,
           Date().timeIntervalSince(fetched) < 60 {
            return data
        }
        guard let request = LyricsHTTP.buildRequest(url: "https://epsilonmusic.ct.ws/canvas.json",
                                                    method: "GET", headers: [:], body: nil, timeout: 10) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        manifestData = data
        manifestFetchedAt = Date()
        return data
    }

    /// Apple Music motion artwork (applecanvas module): iTunes album lookup →
    /// AMP API editorialVideo. Falls back to a static JWT-less attempt.
    static func appleMusicCanvas(album: String?, artist: String, song: String? = nil) async -> CanvasArtwork? {
        var query = song ?? album ?? artist
        if let album = album, query == song {
            query = "\(album) \(artist)"
        }
        guard !query.isEmpty else { return nil }
        let itunesUrl = "https://itunes.apple.com/search?media=music&entity=album&term=\(urlEscaped(query))&limit=5"
        guard let (_, parsed) = await LyricsHTTP.get(url: itunesUrl, timeout: 10),
              let json = parsed as? [String: Any],
              let results = JSON.asArray(json["results"]) else { return nil }
        var albumId: String?
        for result in results {
            guard let resultDict = result as? [String: Any] else { continue }
            let candidateArtist = normalize(JSON.asString(resultDict["artistName"]) ?? "")
            let candidateAlbum = normalize(JSON.asString(resultDict["collectionName"]) ?? "")
            let wantedArtist = normalize(artist)
            let wantedAlbum = normalize(album ?? "")
            let artistOk = wantedArtist.isEmpty || candidateArtist.contains(wantedArtist) || wantedArtist.contains(candidateArtist)
            let albumOk = wantedAlbum.isEmpty || candidateAlbum.contains(wantedAlbum) || wantedAlbum.contains(candidateAlbum)
            if (artistOk && albumOk) || albumId == nil {
                albumId = JSON.asString(resultDict["collectionId"])
            }
        }
        guard let id = albumId else { return nil }
        // AMP API motion artwork needs a web JWT; try the public amp endpoint without one.
        let ampUrl = "https://amp-api.music.apple.com/v1/catalog/us/albums/\(id)?extend=editorialVideo"
        guard let request = LyricsHTTP.buildRequest(url: ampUrl, method: "GET",
                                                    headers: ["Origin": "https://music.apple.com"], body: nil, timeout: 10) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = JSON.parse(data) else { return nil }
        if let video = JSON.dig(json, "data", 0, "attributes", "editorialVideo") {
            let motion = JSON.asDict(JSON.dig(video, "motionDetailSquare")) ?? JSON.asDict(JSON.dig(video, "standardSquare"))
            let videoUrl = JSON.asString(JSON.dig(motion, "video")) ?? JSON.asString(motion["previewVideo"])
            let artwork = JSON.asString(JSON.dig(json, "data", 0, "attributes", "artwork", "url"))?
                .replacingOccurrences(of: "{w}", with: "1000")
                .replacingOccurrences(of: "{h}", with: "1000")
            if let videoUrl = videoUrl {
                return CanvasArtwork(animatedUrl: nil, videoUrl: videoUrl, staticUrl: artwork)
            }
        }
        return nil
    }

    /// Provider cascade (Thumbnail.kt canvas lookup order).
    static func lookupCanvas(song: Song) async -> CanvasArtwork? {
        let title = normalize(song.title)
        let artist = normalize(song.artistsText)
        if title.isEmpty || artist.isEmpty { return nil }
        if let result = await appleMusicCanvas(album: song.album, artist: song.artistsText, song: song.title) {
            return result
        }
        if let result = await epsilonMusicCanvas(title: song.title, artist: song.artistsText) {
            return result
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "(official music video)", with: "")
            .replacingOccurrences(of: "(official video)", with: "")
            .replacingOccurrences(of: "(lyrics)", with: "")
            .replacingOccurrences(of: "(audio)", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
