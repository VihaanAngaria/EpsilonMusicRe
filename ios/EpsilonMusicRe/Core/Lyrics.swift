import Foundation

/// Synced lyrics via lrclib — the free lyrics API also used by the Android
/// app's `lrclib` module. Falls back to plain (unsynced) lyrics.
enum LyricsProvider {

    static func fetchLyrics(for song: Song) async -> Lyrics? {
        let artist = song.artistsText
        let title = cleanTitle(song.title)

        var components = URLComponents(string: "https://lrclib.net/api/search")
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("EpsilonMusicRe-iOS/1.0 (https://github.com/VihaanAngaria/EpsilonMusicRe)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let json = JSON.parse(data)
            guard let results = JSON.asArray(json), !results.isEmpty else { return nil }

            // Prefer the first result with synced lyrics.
            for result in results {
                if let synced = JSON.asString(JSON.dig(result, "syncedLyrics")), !synced.isEmpty,
                   let lines = parseLRC(synced) {
                    return Lyrics(lines: lines, isSynced: true, sourceName: "LRCLIB")
                }
            }
            if let first = results.first,
               let plain = JSON.asString(JSON.dig(first, "plainLyrics")), !plain.isEmpty {
                let lines = plain.components(separatedBy: "\n").map { text in
                    LyricsLine(time: -1, text: text)
                }
                return Lyrics(lines: lines, isSynced: false, sourceName: "LRCLIB")
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Strips "(Official ...)", "[...]" suffixes that hurt matching.
    static func cleanTitle(_ title: String) -> String {
        var t = title
        let patterns = [
            "\\s*\\(Official[^)]*\\)",
            "\\s*\\(Official\\)",
            "\\s*\\(Lyrics?[^)]*\\)",
            "\\s*\\(Audio[^)]*\\)",
            "\\s*\\(Video[^)]*\\)",
            "\\s*\\[Official[^]]*\\]",
            "\\s*\\[Lyrics?[^]]*\\]",
            "\\s*\\[Audio[^]]*\\]",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(t.startIndex..., in: t)
                t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses an LRC document into timed lines.
    static func parseLRC(_ lrc: String) -> [LyricsLine]? {
        var lines: [LyricsLine] = []
        for rawLine in lrc.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            // One or more [mm:ss.xx] prefixes may precede the text.
            var remaining = line
            var times: [Double] = []
            while remaining.hasPrefix("[") {
                guard let closeIndex = remaining.firstIndex(of: "]") else { break }
                let stamp = String(remaining[remaining.index(after: remaining.startIndex)..<closeIndex])
                if let time = parseTimestamp(stamp) {
                    times.append(time)
                    remaining = String(remaining[remaining.index(after: closeIndex)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
            }
            if times.isEmpty { continue }
            for time in times {
                lines.append(LyricsLine(time: time, text: remaining))
            }
        }
        guard !lines.isEmpty else { return nil }
        lines.sort { $0.time < $1.time }
        return lines
    }

    static func parseTimestamp(_ stamp: String) -> Double? {
        // "mm:ss.xx" or "mm:ss,xxx" or "hh:mm:ss.xx"
        let cleaned = stamp.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty, parts.count >= 2, parts.count <= 3 else { return nil }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return parts[0] * 60 + parts[1]
    }

    /// Index of the active line for a playback position.
    static func activeLineIndex(for lyrics: Lyrics, position: Double) -> Int? {
        guard lyrics.isSynced, !lyrics.lines.isEmpty else { return nil }
        var active: Int? = nil
        for (index, line) in lyrics.lines.enumerated() {
            if line.time <= position + 0.2 {
                active = index
            } else {
                break
            }
        }
        return active
    }
}
