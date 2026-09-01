import Foundation
import Combine

/// Download manager — the iOS counterpart of the Android app's Media3 download
/// service. Resolves the same progressive AAC stream InnerTube plays and stores
/// it under Documents/Downloads/<videoId>.m4a so playback works offline and the
/// "Downloaded" library section has real content. Track progress, size and
/// clearing mirror the Android StorageSettings behaviors.
@MainActor
final class DownloadManager: NSObject, ObservableObject {

    static let shared = DownloadManager()

    enum DownloadState: Equatable {
        case queued
        case downloading(progress: Double)
        case completed(sizeBytes: Int64)
        case failed(String)
    }

    @Published var states: [String: DownloadState] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]
    private var urlSessions: [String: URLSession] = [:]

    var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileUrl(for videoId: String) -> URL {
        downloadsDirectory.appendingPathComponent("\(sanitize(videoId)).m4a")
    }

    private func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    // MARK: Queries

    func isDownloaded(_ song: Song) -> Bool {
        isDownloadedId(song.id)
    }

    func isDownloadedId(_ id: String) -> Bool {
        let file = fileUrl(for: id)
        if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64, size > 10_000 {
            return true
        }
        return false
    }

    func localFileUrl(for song: Song) -> URL? {
        let file = fileUrl(for: song.id)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// All downloaded songs from the library (liked + history + playlists) —
    /// the Android "Cache playlist" concept.
    func downloadedSongs() -> [Song] {
        let library = LibraryStore.shared
        var seen: Set<String> = []
        var out: [Song] = []
        for song in library.likedSongs + library.history.map(\.song) + library.playlists.flatMap(\.songs) {
            if seen.insert(song.id).inserted, isDownloaded(song) {
                out.append(song)
            }
        }
        return out
    }

    func totalSizeBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: Download

    func download(_ song: Song) {
        guard !isDownloaded(song) else {
            states[song.id] = .completed(sizeBytes: 0)
            return
        }
        guard tasks[song.id] == nil else { return }
        states[song.id] = .queued
        tasks[song.id] = Task { [weak self] in
            await self?.performDownload(song)
        }
    }

    private func performDownload(_ song: Song) async {
        do {
            let stream = try await InnerTube.shared.resolveStream(videoId: song.videoId)
            guard !Task.isCancelled else { return }
            let (data, response) = try await URLSession.shared.data(from: stream.url)
            guard !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                states[song.id] = .failed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                tasks[song.id] = nil
                return
            }
            let destination = fileUrl(for: song.id)
            try data.write(to: destination, options: .atomic)
            states[song.id] = .completed(sizeBytes: Int64(data.count))
            // Record in the library so the download survives cache clears.
            LibraryStore.shared.markDownloaded(song)
            tasks[song.id] = nil
        } catch {
            states[song.id] = .failed(error.localizedDescription)
            tasks[song.id] = nil
        }
    }

    /// Progress polling for the player download button (progress is chunkless here;
    /// approximate by fetching expected length then tracking via delegate-free polling).
    func remove(_ song: Song) {
        tasks[song.id]?.cancel()
        tasks[song.id] = nil
        try? FileManager.default.removeItem(at: fileUrl(for: song.id))
        states.removeValue(forKey: song.id)
        LibraryStore.shared.markUndownloaded(song)
    }

    func removeAll() {
        for song in downloadedSongs() {
            remove(song)
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
        states.removeAll()
    }

    // MARK: Song cache (transient stream cache — Android's SimpleCache equivalent)

    var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = caches.appendingPathComponent("stream-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func clearSongCache() {
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }

    func clearImageCache() {
        URLCache.shared.removeAllCachedResponses()
    }
}
