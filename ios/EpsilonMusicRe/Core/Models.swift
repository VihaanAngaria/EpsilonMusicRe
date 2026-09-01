import Foundation
import SwiftUI

// MARK: - Song

struct Song: Identifiable, Equatable, Codable, Hashable {
    var videoId: String
    var title: String
    var artists: [String]
    var album: String?
    var duration: Int?            // seconds
    var thumbnail: String?        // remote URL
    var isLocal: Bool             // device music library (MPMediaItem) or bundled demo
    var localKey: String?         // persistent ID (MPMediaItem) or bundle resource name
    var isDemo: Bool

    var id: String {
        isLocal ? "local-\(localKey ?? videoId)" : videoId
    }

    var artistsText: String {
        artists.joined(separator: ", ")
    }

    var subtitle: String {
        var parts: [String] = []
        if !artistsText.isEmpty { parts.append(artistsText) }
        if let album = album, !album.isEmpty { parts.append(album) }
        if let d = duration, d > 0 { parts.append(formatDuration(d)) }
        return parts.joined(separator: " • ")
    }

    /// Thumbnail for display — always returns something usable.
    var thumbnailUrl: String? {
        if let t = thumbnail, !t.isEmpty { return t }
        if !videoId.isEmpty && !isLocal { return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg" }
        return nil
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Artist

struct ArtistItem: Identifiable, Codable, Hashable {
    var browseId: String
    var name: String
    var thumbnail: String?
    var playCount: Int?

    var id: String { browseId }
}

// MARK: - Album

struct AlbumItem: Identifiable, Codable, Hashable {
    var browseId: String
    var title: String
    var artists: [String]
    var year: String?
    var thumbnail: String?
    var isSingle: Bool

    var id: String { browseId }
    var artistsText: String { artists.joined(separator: ", ") }
}

// MARK: - Playlist (online)

struct PlaylistItem: Identifiable, Codable, Hashable {
    var browseId: String          // "VL..." / "RD..." / "OL..."
    var title: String
    var owner: String?
    var countText: String?
    var thumbnail: String?
    var isLocal: Bool

    var id: String { browseId }
}

// MARK: - Local playlist (persisted)

struct LocalPlaylist: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var createdAt: Double
    var songs: [Song]

    var songCount: Int { songs.count }
    var thumbnailUrl: String? { songs.first?.thumbnailUrl }
}

// MARK: - Grid item (home/explore carousels)

enum MediaGridItem: Identifiable {
    case song(Song)
    case artist(ArtistItem)
    case album(AlbumItem)
    case playlist(PlaylistItem)

    var id: String {
        switch self {
        case .song(let s): return "s-\(s.id)"
        case .artist(let a): return "a-\(a.id)"
        case .album(let a): return "al-\(a.id)"
        case .playlist(let p): return "p-\(p.id)"
        }
    }

    var title: String {
        switch self {
        case .song(let s): return s.title
        case .artist(let a): return a.name
        case .album(let a): return a.title
        case .playlist(let p): return p.title
        }
    }

    var subtitle: String {
        switch self {
        case .song(let s): return s.artistsText
        case .artist(let a): return a.playCount.map { formatPlayCount($0) } ?? "Artist"
        case .album(let a): return a.year ?? a.artistsText
        case .playlist(let p): return [p.owner, p.countText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • ")
        }
    }

    var thumbnail: String? {
        switch self {
        case .song(let s): return s.thumbnailUrl
        case .artist(let a): return a.thumbnail
        case .album(let a): return a.thumbnail
        case .playlist(let p): return p.thumbnail
        }
    }
}

// MARK: - Shelf (home / artist sections)

struct Shelf: Identifiable {
    var title: String
    var subtitle: String?
    var items: [MediaGridItem]

    var id: String { title }
}

// MARK: - Lyrics

struct LyricsLine: Identifiable, Equatable {
    var time: Double    // seconds, -1 = unsynced
    var text: String

    var id: Int { text.hashValue }
}

struct Lyrics {
    var lines: [LyricsLine]
    var isSynced: Bool
    var sourceName: String
}

// MARK: - History / stats

struct HistoryEntry: Codable, Identifiable {
    var song: Song
    var playedAt: Double

    var id: String { "\(song.id)-\(Int(playedAt))" }
}

// MARK: - Formatting helpers

func formatDuration(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, sec)
    }
    return String(format: "%d:%02d", m, sec)
}

func formatPlayCount(_ count: Int) -> String {
    if count >= 1_000_000_000 {
        return String(format: "%.1fB plays", Double(count) / 1_000_000_000)
    }
    if count >= 1_000_000 {
        return String(format: "%.1fM plays", Double(count) / 1_000_000)
    }
    if count >= 1_000 {
        return String(format: "%.1fK plays", Double(count) / 1_000)
    }
    return "\(count) plays"
}
