import Foundation

// MARK: - Provider registry (LyricsProviderRegistry.kt parity)

enum LyricsProviderName: String, CaseIterable, Identifiable {
    case youLyPlus = "YouLyPlus"
    case paxsenix = "Paxsenix"
    case unison = "Unison"
    case betterLyrics = "BetterLyrics"
    case simpmusic = "SimpMusic"
    case lrcLib = "LrcLib"
    case kugou = "Kugou"
    case youtubeSubtitle = "YouTubeSubtitle"
    case youtubeMusic = "YouTubeMusic"

    var id: String { rawValue }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "lyrics_enabled_\(rawValue)") as? Bool ?? true
    }

    static var order: [LyricsProviderName] {
        get {
            if let saved = UserDefaults.standard.string(forKey: "lyricsProviderOrder") {
                let names = saved.split(separator: ",").compactMap { LyricsProviderName(rawValue: String($0)) }
                let remainder = allCases.filter { !names.contains($0) }
                return names + remainder
            }
            return allCases
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).joined(separator: ","), forKey: "lyricsProviderOrder")
        }
    }
}

// MARK: - Fetch orchestration

enum LyricsAggregator {

    /// Fetches lyrics through the provider chain in user-configured order.
    static func fetchLyrics(for song: Song) async -> Lyrics? {
        if song.isLocal { return nil }
        let duration = song.duration ?? 0
        for provider in LyricsProviderName.order {
            guard provider.isEnabled else { continue }
            if Task.isCancelled { return nil }
            if let lyrics = await fetch(from: provider, song: song, duration: duration) {
                return lyrics
            }
        }
        return nil
    }

    static func fetch(from provider: LyricsProviderName, song: Song, duration: Int) async -> Lyrics? {
        switch provider {
        case .youLyPlus: return await YouLyPlus.get(song: song, duration: duration)
        case .paxsenix: return await Paxsenix.get(song: song, duration: duration)
        case .unison: return await Unison.get(song: song, duration: duration)
        case .betterLyrics: return await BetterLyrics.get(song: song, duration: duration)
        case .simpmusic: return await SimpMusic.get(videoId: song.videoId, duration: duration)
        case .lrcLib: return await LrcLib.get(song: song)
        case .kugou: return await KuGou.get(song: song, duration: duration)
        case .youtubeSubtitle:
            let lines = (await InnerTube.shared.transcript(videoId: song.videoId))?.lines
            if let lines = lines, !lines.isEmpty {
                return Lyrics(lines: lines, isSynced: true, sourceName: "YouTube")
            }
            return nil
        case .youtubeMusic:
            return await InnerTube.shared.youtubeMusicLyrics(videoId: song.videoId)
        }
    }
}

// MARK: - LRC parsing

enum LRCParser {
    static let lineRegex = try? NSRegularExpression(pattern: "\\[(\\d\\d):(\\d\\d)\\.(\\d{2,3})\\] ?")

    /// Parses plain LRC (incl. multi-timestamp lines) into timed lines.
    static func parse(_ lrc: String) -> [LyricsLine]? {
        var out: [LyricsLine] = []
        for rawLine in lrc.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard let regex = lineRegex else { continue }
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else {
                // Metadata or unsynced text — keep only meaningful text.
                if !line.hasPrefix("[") && !line.isEmpty {
                    out.append(LyricsLine(time: -1, text: line))
                }
                continue
            }
            let textRange = NSRange(line.startIndex..., in: line)
            var text = line
            var timestamps: [Double] = []
            for match in matches.reversed() {
                if let minuteRange = Range(match.range(at: 1), in: line),
                   let secondRange = Range(match.range(at: 2), in: line),
                   let centiRange = Range(match.range(at: 3), in: line),
                   let minutes = Double(line[minuteRange]),
                   let seconds = Double(line[secondRange]),
                   let centis = Double(line[centiRange]) {
                    timestamps.append(minutes * 60 + seconds + centis / 100.0)
                }
                text = (text as NSString).replacingCharacters(in: match.range, with: "")
            }
            let cleaned = text.trimmingCharacters(in: .whitespaces)
            for ts in timestamps {
                out.append(LyricsLine(time: ts, text: cleaned))
            }
        }
        out.sort { $0.time < $1.time }
        return out.isEmpty ? nil : out
    }

    /// Extracts word timings from a `LyricsLine`-predecessor marker line
    /// (`<word:start:end|word:start:end>` or `<mm:ss.mmm>word` forms).
    static func parseWordTimings(_ line: String) -> [(text: String, start: Double, end: Double)]? {
        guard line.hasPrefix("<") && line.hasSuffix(">") else { return nil }
        let inner = String(line.dropFirst().dropLast())
        if inner.contains(":") {
            // <mm:ss.mmm>word format
            let parts = inner.components(separatedBy: ">")
            var out: [(String, Double, Double)] = []
            for part in parts {
                let comp = part.components(separatedBy: "<")
                // comp = ["mm:ss.mmm", "word"]
                if comp.count == 2, let t = Self.parseTimestamp(comp[0]) {
                    out.append((comp[1], t, t))
                }
            }
            return out.isEmpty ? nil : out
        }
        var out: [(String, Double, Double)] = []
        for segment in inner.components(separatedBy: "|") {
            let bits = segment.components(separatedBy: ":")
            if bits.count == 3, let start = Double(bits[1]), let end = Double(bits[2]) {
                out.append((bits[0], start, end))
            }
        }
        return out.isEmpty ? nil : out
    }

    static func parseTimestamp(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
        return m * 60 + s
    }
}

// MARK: - TTML parser (BetterLyrics TTMLParser.kt parity, word timings)

enum TTMLParser {
    static func parse(_ ttml: String) -> Lyrics? {
        var lines: [LyricsLine] = []
        // Split on <p ...> ... </p> elements.
        let regex = try? NSRegularExpression(pattern: "<p\\b[^>]*\\bbegin=\"([^\"]+)\"[^>]*>(.*?)</p>", options: [.dotMatchesLineSeparators])
        if let regex = regex {
            let ns = ttml as NSString
            let matches = regex.matches(in: ttml, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let begin = ns.substring(with: match.range(at: 1))
                let content = ns.substring(with: match.range(at: 2))
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                let text = decodeXMLEntities(content).trimmingCharacters(in: .whitespacesAndNewlines)
                if let seconds = Self.parseTimestamp(begin), !text.isEmpty {
                    lines.append(LyricsLine(time: seconds, text: text))
                }
            }
        }
        guard !lines.isEmpty else { return nil }
        lines.sort { $0.time < $1.time }
        return Lyrics(lines: lines, isSynced: true, sourceName: "TTML")
    }

    static func parseTimestamp(_ iso: String) -> Double? {
        // "00:01:02.345" / "62.34s" / "0:01.23"
        var s = iso
        if s.hasSuffix("s") || s.hasSuffix("t") { s = String(s.dropLast()) }
        let parts = s.split(separator: ":")
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let sec = Double(parts[2]) ?? 0
            return h * 3600 + m * 60 + sec
        }
        if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let sec = Double(parts[1]) ?? 0
            return m * 60 + sec
        }
        return Double(s)
    }

    static func decodeXMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

// MARK: - Shared HTTP helper

enum LyricsHTTP {
    static func get(url: String, headers: [String: String] = [:], timeout: Double = 15) async -> (Data, Any)? {
        guard let request = buildRequest(url: url, method: "GET", headers: headers, body: nil, timeout: timeout) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = JSON.parse(data) else { return nil }
        return (data, json)
    }

    static func buildRequest(url: String, method: String, headers: [String: String], body: Data?, timeout: Double) -> URLRequest? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        return request
    }
}

// MARK: - Individual providers

enum YouLyPlus {
    static let servers = [
        "https://lyricsplus.prjktla.my.id",
        "https://lyricsplus.atomix.one",
        "https://lyricsplus.binimum.org",
        "https://lyricsplus.prjktla.workers.dev",
        "https://lyricsplus-seven.vercel.app",
        "https://lyrics-plus-backend.vercel.app",
    ]

    static func get(song: Song, duration: Int) async -> Lyrics? {
        for server in servers {
            var components = URLComponents(string: "\(server)/v2/lyrics/get")
            var items = [URLQueryItem(name: "title", value: song.title),
                         URLQueryItem(name: "artist", value: song.artistsText)]
            if duration > 0 { items.append(URLQueryItem(name: "duration", value: "\(duration)")) }
            components?.queryItems = items
            guard let url = components?.url?.absoluteString else { continue }
            guard let (_, json) = await LyricsHTTP.get(url: url, timeout: 8) else { continue }
            if let synced = JSON.asString(JSON.dig(json, "syncedLyrics")), !synced.isEmpty,
               let lines = LRCParser.parse(synced) {
                return Lyrics(lines: lines, isSynced: true, sourceName: "YouLyPlus")
            }
            if let array = JSON.asArray(JSON.dig(json, "lyrics")) {
                var lines: [LyricsLine] = []
                for item in array {
                    let ms = JSON.asInt(JSON.dig(item, "time")) ?? 0
                    let text = JSON.asString(JSON.dig(item, "text")) ?? ""
                    if !text.isEmpty {
                        lines.append(LyricsLine(time: Double(ms) / 1000.0, text: text))
                    }
                }
                if !lines.isEmpty {
                    return Lyrics(lines: lines, isSynced: true, sourceName: "YouLyPlus")
                }
            }
            if let plain = JSON.asString(JSON.dig(json, "plainLyrics")), !plain.isEmpty {
                let lines = plain.components(separatedBy: "\n").map { LyricsLine(time: -1, text: $0) }
                return Lyrics(lines: lines, isSynced: false, sourceName: "YouLyPlus")
            }
        }
        return nil
    }
}

enum Paxsenix {
    static func get(song: Song, duration: Int) async -> Lyrics? {
        let query = "\(song.artistsText) \(song.title)".trimmingCharacters(in: .whitespaces)
        let url = "https://lyrics.paxsenix.org/apple-music/search?q=\(urlEscaped(query))"
        guard let (_, json) = await LyricsHTTP.get(url: url, headers: ["User-Agent": "epsilonmusic/1.0"], timeout: 6) else { return nil }
        guard let results = JSON.asArray(json), let first = results.first else { return nil }
        let id = JSON.asInt(JSON.dig(first, "id")) ?? JSON.asInt(JSON.dig(first, "trackId")) ?? 0
        guard id != 0 else { return nil }
        // Duration sanity (±2s scoring simplified to ±3s window).
        if duration > 0, let ms = JSON.asInt(JSON.dig(first, "duration")), ms > 0 {
            let diff = abs(ms - duration * 1000)
            if diff > 12_000 { return nil }
        }
        guard let (_, lyricsJson) = await LyricsHTTP.get(url: "https://lyrics.paxsenix.org/apple-music/lyrics?id=\(id)", headers: ["User-Agent": "epsilonmusic/1.0"], timeout: 6) else { return nil }
        if let ttml = JSON.asString(JSON.dig(lyricsJson, "ttmlContent")), let parsed = TTMLParser.parse(ttml) {
            return Lyrics(lines: parsed.lines, isSynced: true, sourceName: "Paxsenix")
        }
        if let elrc = JSON.asString(JSON.dig(lyricsJson, "elrc")), let lines = LRCParser.parse(elrc) {
            return Lyrics(lines: lines, isSynced: true, sourceName: "Paxsenix")
        }
        // content[] synthesis.
        if let content = JSON.asArray(JSON.dig(lyricsJson, "content")) {
            var lines: [LyricsLine] = []
            for line in content {
                let ts = JSON.asString(JSON.dig(line, "timestamp")) ?? ""
                let text = JSON.asString(JSON.dig(line, "text")) ?? ""
                let time = LRCParser.parseTimestamp(ts) ?? -1
                if !text.isEmpty { lines.append(LyricsLine(time: time, text: text)) }
            }
            if !lines.isEmpty {
                let synced = lines.contains { $0.time >= 0 }
                return Lyrics(lines: synced ? lines : lines.map { LyricsLine(time: -1, text: $0.text) }, isSynced: synced, sourceName: "Paxsenix")
            }
        }
        if let plain = JSON.asString(JSON.dig(lyricsJson, "plain")), !plain.isEmpty {
            let lines = plain.components(separatedBy: "\n").map { LyricsLine(time: -1, text: $0) }
            return Lyrics(lines: lines, isSynced: false, sourceName: "Paxsenix")
        }
        return nil
    }
}

enum Unison {
    static func get(song: Song, duration: Int) async -> Lyrics? {
        var components = URLComponents(string: "https://unison.boidu.dev/lyrics")
        var items = [URLQueryItem(name: "song", value: song.title),
                     URLQueryItem(name: "artist", value: song.artistsText)]
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: "\(duration)")) }
        components?.queryItems = items
        guard let url = components?.url?.absoluteString else { return nil }
        guard let (_, json) = await LyricsHTTP.get(url: url, timeout: 8) else { return nil }
        guard JSON.asBool(JSON.dig(json, "success")) != false else { return nil }
        guard let raw = JSON.asString(JSON.dig(json, "data", "lyrics")), !raw.isEmpty else { return nil }
        if raw.hasPrefix("<?xml") || raw.contains("<tt ") {
            if let parsed = TTMLParser.parse(raw) {
                return Lyrics(lines: parsed.lines, isSynced: true, sourceName: "Unison")
            }
        }
        if let lines = LRCParser.parse(raw) {
            let synced = lines.contains { $0.time >= 0 }
            return Lyrics(lines: lines, isSynced: synced, sourceName: "Unison")
        }
        return nil
    }
}

enum BetterLyrics {
    static func get(song: Song, duration: Int) async -> Lyrics? {
        var components = URLComponents(string: "https://lyrics-api.boidu.dev/getLyrics")
        var items = [URLQueryItem(name: "s", value: song.title),
                     URLQueryItem(name: "a", value: song.artistsText)]
        if duration > 0 { items.append(URLQueryItem(name: "d", value: "\(duration)")) }
        components?.queryItems = items
        guard let url = components?.url?.absoluteString else { return nil }
        guard let (_, json) = await LyricsHTTP.get(url: url, timeout: 15) else { return nil }
        guard let ttml = JSON.asString(JSON.dig(json, "ttml")), !ttml.isEmpty else { return nil }
        return TTMLParser.parse(ttml)
    }
}

enum SimpMusic {
    static func get(videoId: String, duration: Int) async -> Lyrics? {
        var url = "https://api-lyrics.simpmusic.org/v1/\(videoId)"
        var headers = ["User-Agent": "SimpMusicLyrics/1.0", "Accept": "application/json"]
        guard let (_, json) = await LyricsHTTP.get(url: url, headers: headers, timeout: 10) else {
            url = "https://vivi-yt-music-server.onrender.com/v1/\(videoId)"
            guard let (_, fallbackJson) = await LyricsHTTP.get(url: url, headers: headers, timeout: 12) else { return nil }
            return parse(fallbackJson, duration: duration)
        }
        headers["Content-Type"] = "application/json"
        return parse(json, duration: duration)
    }

    static func parse(_ json: Any, duration: Int) -> Lyrics? {
        guard let data = JSON.asArray(JSON.dig(json, "data")) else { return nil }
        for entry in data {
            if let rich = JSON.asString(JSON.dig(entry, "richSyncLyrics")), let lines = LRCParser.parse(rich) {
                return Lyrics(lines: lines, isSynced: true, sourceName: "SimpMusic")
            }
            if let synced = JSON.asString(JSON.dig(entry, "syncedLyrics")), let lines = LRCParser.parse(synced) {
                return Lyrics(lines: lines, isSynced: true, sourceName: "SimpMusic")
            }
            if let plain = JSON.asString(JSON.dig(entry, "plainLyrics")), !plain.isEmpty {
                let lines = plain.components(separatedBy: "\n").map { LyricsLine(time: -1, text: $0) }
                return Lyrics(lines: lines, isSynced: false, sourceName: "SimpMusic")
            }
        }
        return nil
    }
}

enum LrcLib {
    static func get(song: Song) async -> Lyrics? {
        let title = LyricsCleanup.cleanTitle(song.title)
        let artist = LyricsCleanup.primaryArtist(song.artistsText)
        var attempts: [(String, String?)] = [
            ("https://lrclib.net/api/search?track_name=\(urlEscaped(title))&artist_name=\(urlEscaped(artist))", nil),
        ]
        if let songAlbum = song.album, !songAlbum.isEmpty {
            attempts.append(("https://lrclib.net/api/search?track_name=\(urlEscaped(title))&artist_name=\(urlEscaped(artist))&album_name=\(urlEscaped(songAlbum))", nil))
        }
        attempts.append(("https://lrclib.net/api/search?q=\(urlEscaped("\(artist) \(title)"))", nil))
        attempts.append(("https://lrclib.net/api/search?q=\(urlEscaped(title))", nil))

        for (url, _) in attempts {
            guard let (_, json) = await LyricsHTTP.get(url: url, timeout: 10),
                  let results = JSON.asArray(json) else { continue }
            // Prefer exact-ish duration match with synced lyrics.
            var best: (score: Int, lyrics: Lyrics)?
            let duration = song.duration ?? 0
            for result in results {
                let synced = JSON.asString(JSON.dig(result, "syncedLyrics")) ?? ""
                let plain = JSON.asString(JSON.dig(result, "plainLyrics")) ?? ""
                let resultDuration = JSON.asDouble(JSON.dig(result, "duration")) ?? 0
                guard !synced.isEmpty || !plain.isEmpty else { continue }
                var score = 0
                if !synced.isEmpty { score += 10 }
                if duration > 0, resultDuration > 0 {
                    let diff = abs(resultDuration - Double(duration))
                    if diff <= 2 { score += 6 } else if diff <= 5 { score += 4 } else if diff <= 10 { score += 1 } else if diff > 15 { continue }
                }
                let lyrics: Lyrics?
                if let lines = LRCParser.parse(synced), !synced.isEmpty {
                    lyrics = Lyrics(lines: lines, isSynced: true, sourceName: "LRCLIB")
                } else if let lines = plain.linesArray() {
                    lyrics = Lyrics(lines: lines, isSynced: false, sourceName: "LRCLIB")
                } else {
                    lyrics = nil
                }
                if let lyrics = lyrics, (best?.score ?? -1) < score {
                    best = (score, lyrics)
                }
            }
            if let best = best { return best.lyrics }
        }
        return nil
    }
}

enum KuGou {
    static func get(song: Song, duration: Int) async -> Lyrics? {
        let keyword = "\(song.title) - \(song.artistsText)"
        guard let (_, json) = await LyricsHTTP.get(url: "https://mobileservice.kugou.com/api/v3/search/song?version=9108&plat=0&pagesize=8&showtype=0&keyword=\(urlEscaped(keyword))", timeout: 10) else { return nil }
        let candidates = JSON.asArray(JSON.dig(json, "data", "info")) ?? []
        var hash: String?
        for candidate in candidates {
            let candidateDuration = JSON.asInt(JSON.dig(candidate, "duration")) ?? 0
            if duration > 0, candidateDuration > 0, abs(candidateDuration - duration) > 8 { continue }
            hash = JSON.asString(JSON.dig(candidate, "hash"))
            break
        }
        guard let hash = hash else { return nil }
        guard let (_, searchJson) = await LyricsHTTP.get(url: "https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&hash=\(hash)", timeout: 10),
              let results = JSON.asArray(JSON.dig(searchJson, "candidates")), let first = results.first else { return nil }
        let id = JSON.asString(JSON.dig(first, "id")) ?? ""
        let accesskey = JSON.asString(JSON.dig(first, "accesskey")) ?? ""
        guard !id.isEmpty, !accesskey.isEmpty else { return nil }
        guard let (_, downloadJson) = await LyricsHTTP.get(url: "https://lyrics.kugou.com/download?fmt=lrc&charset=utf8&client=pc&ver=1&id=\(id)&accesskey=\(accesskey)", timeout: 10) else { return nil }
        guard let content = JSON.asString(JSON.dig(downloadJson, "content")),
              let data = Data(base64Encoded: content) else { return nil }
        guard var lrc = String(data: data, encoding: .utf8) else { return nil }
        // KuGou normalize: keep timestamped lines and plain text, drop [ar:…] metadata.
        lrc = lrc.components(separatedBy: "\n")
            .filter { line in
                !line.hasPrefix("[") || line.range(of: "^\\[\\d", options: .regularExpression) != nil
            }
            .joined(separator: "\n")
        if let lines = LRCParser.parse(lrc) {
            let synced = lines.contains { $0.time >= 0 }
            return Lyrics(lines: lines, isSynced: synced, sourceName: "KuGou")
        }
        return nil
    }
}

// MARK: - Cleanup helpers (LrcLib.kt parity)

enum LyricsCleanup {
    static func cleanTitle(_ title: String) -> String {
        var t = title
        let patterns = [
            "\\s*\\(Official[^)]*\\)", "\\s*\\(Official\\)", "\\s*\\(Lyrics?[^)]*\\)",
            "\\s*\\(Audio[^)]*\\)", "\\s*\\(Video[^)]*\\)", "\\s*\\[Official[^]]*\\]",
            "\\s*\\[Lyrics?[^]]*\\]", "\\s*\\[Audio[^]]*\\]", "\\s*\\[Video[^]]*\\]",
            "\\s*\\(MV\\)", "\\s*\\(M/V\\)",
        ]
        for pattern in patterns {
            t = t.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Drops featured artists after the first separator (LrcLib primary-artist rule).
    static func primaryArtist(_ artist: String) -> String {
        for separator in [" & ", " ft. ", " ft ", " feat. ", " feat ", " x ", " × "] {
            if let range = artist.range(of: separator) {
                return String(artist[artist.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return artist
    }
}

func urlEscaped(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
}

extension String {
    func linesArray() -> [LyricsLine]? {
        let lines = components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.map { LyricsLine(time: -1, text: $0) }
    }
}

extension JSON {
    static func asBool(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return nil
    }
}
