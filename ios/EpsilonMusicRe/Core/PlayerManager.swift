import Foundation
import Combine
import AVFoundation
import MediaPlayer
import UIKit

enum RepeatMode: Int, CaseIterable {
    case off, all, one
}

/// Streaming queue player — the iOS counterpart of the Android playback module
/// (Media3 service + queue controller). Resolves progressive streams through the
/// InnerTube client (ANDROID_VR first, matching the Android app's fallback order),
/// plays them with AVPlayer and keeps the lock-screen / control-center surface
/// (MPNowPlayingInfoCenter + MPRemoteCommandCenter) in sync.
@MainActor
final class PlayerManager: NSObject, ObservableObject {

    static let shared = PlayerManager()

    // MARK: State

    @Published var currentSong: Song?
    @Published var queue: [Song] = []
    @Published private(set) var originalQueue: [Song] = []
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var errorMessage: String?
    @Published var queueSourceName: String = ""

    // Sleep timer (mirrors the Android player's sleep timer).
    @Published var sleepRemaining: Int = 0
    private var sleepTimer: Timer?
    private var sleepAtEndOfTrack = false

    // Dynamic theme feedback.
    @Published var artworkDominantColor: UIColor?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var resolvedUrls: [String: URL] = [:]
    private var reResolveAttempted = false
    private var cancellables: Set<AnyCancellable> = []
    private var lastArtwork: UIImage?
    private var sessionConfigured = false

    var currentIndex: Int {
        guard let current = currentSong else { return -1 }
        return queue.firstIndex(where: { $0.id == current.id }) ?? -1
    }

    var upNextSongs: [Song] {
        guard let current = currentSong, let index = queue.firstIndex(where: { $0.id == current.id }) else {
            return Array(queue.prefix(20))
        }
        return Array(queue.dropFirst(index + 1))
    }

    private override init() {
        super.init()
        installObservers()
    }

    // MARK: Setup

    private func configureAudioSession() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            // Non-fatal — playback still works in the foreground.
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func installObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.tick(time)
            }
        }

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleTrackEnded()
                }
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                    if status == .playing {
                        self.isPlaying = true
                    }
                }
            }
            .store(in: &cancellables)

        // Item failure -> try one re-resolve (stream URLs expire), then skip.
        player.publisher(for: \.currentItem?.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in
                    guard let self = self, let status = status else { return }
                    if status == .failed {
                        self.handleItemError()
                    }
                }
            }
            .store(in: &cancellables)

        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = posEvent.positionTime
            Task { @MainActor in self?.seek(to: seconds) }
            return .success
        }
    }

    // MARK: Public transport controls

    func play(_ song: Song, queue songs: [Song] = [], sourceName: String = "") {
        var finalQueue = songs.isEmpty ? [song] : songs
        if !finalQueue.contains(where: { $0.id == song.id }) {
            finalQueue.insert(song, at: 0)
        }
        self.queue = finalQueue
        self.originalQueue = finalQueue
        if shuffle {
            applyShuffle(keeping: song)
        }
        queueSourceName = sourceName
        errorMessage = nil
        load(song)
    }

    func playAt(index: Int) {
        guard index >= 0, index < queue.count else { return }
        load(queue[index])
    }

    func playNext(_ song: Song) {
        if currentSong == nil {
            play(song)
            return
        }
        if let index = queue.firstIndex(where: { $0.id == song.id }) {
            queue.remove(at: index)
        }
        let currentIdx = currentIndex
        if currentIdx >= 0 {
            queue.insert(song, at: currentIdx + 1)
        } else {
            queue.append(song)
        }
        originalQueue = queue
    }

    func addToQueue(_ song: Song) {
        if currentSong == nil {
            play(song)
            return
        }
        if queue.contains(where: { $0.id == song.id }) { return }
        queue.append(song)
        originalQueue = queue
    }

    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        let target = queue[index]
        if target.id == currentSong?.id { return } // don't remove the playing song
        queue.remove(at: index)
        originalQueue = queue
    }

    func clearQueue(keepingCurrent: Bool = true) {
        if keepingCurrent, let current = currentSong {
            queue = [current]
        } else {
            stop()
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard currentSong != nil else { return }
        configureAudioSession()
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying(rate: 0)
    }

    func stop() {
        player.replaceCurrentItem(with: nil)
        currentSong = nil
        isPlaying = false
        position = 0
        duration = 0
        queue = []
        originalQueue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        let target = max(0, seconds)
        let seekTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.position = target
                self?.updateNowPlaying()
            }
        }
    }

    func next(auto: Bool = false) {
        if queue.isEmpty { return }
        // Sleep timer "end of track" handling.
        if auto && sleepAtEndOfTrack {
            sleepAtEndOfTrack = false
            pause()
            clearSleepTimer()
            return
        }
        let index = currentIndex
        if index >= 0 && index + 1 < queue.count {
            load(queue[index + 1])
        } else if repeatMode == .all && !queue.isEmpty {
            load(queue[0])
        } else if auto && AppSettings.shared.autoplayRelated {
            startAutoplayRadio()
        } else {
            pause()
        }
    }

    func previous() {
        // Android behavior: restart when > 3 s into the track, otherwise go back.
        if position > 3 {
            seek(to: 0)
            return
        }
        let index = currentIndex
        if index > 0 {
            load(queue[index - 1])
        } else if repeatMode == .all && !queue.isEmpty {
            load(queue[queue.count - 1])
        } else {
            seek(to: 0)
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
        guard let current = currentSong else { return }
        if shuffle {
            applyShuffle(keeping: current)
        } else {
            queue = originalQueue
        }
    }

    private func applyShuffle(keeping current: Song) {
        var rest = queue.filter { $0.id != current.id }
        rest.shuffle()
        queue = [current] + rest
    }

    func cycleRepeat() {
        repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off
    }

    /// "Start radio" — replaces the queue with the song's radio mix.
    func startRadio(for song: Song) {
        queueSourceName = "Radio"
        play(song, queue: [song], sourceName: "Radio")
        Task { @MainActor in
            do {
                let radio = try await InnerTube.shared.radio(videoId: song.videoId)
                let filtered = radio.filter { $0.videoId != song.videoId }
                if !filtered.isEmpty {
                    queue = [song] + filtered
                    originalQueue = queue
                }
            } catch {
                // Radio is best-effort; keep playing the single song.
            }
        }
    }

    /// Autoplay: fetch radio for the last song and keep playing.
    private func startAutoplayRadio() {
        guard let last = queue.last, !last.isLocal else {
            pause()
            return
        }
        isBuffering = true
        Task { @MainActor in
            do {
                let radio = try await InnerTube.shared.radio(videoId: last.videoId)
                let filtered = radio.filter { r in !queue.contains(where: { $0.videoId == r.videoId }) }
                if filtered.isEmpty {
                    pause()
                    return
                }
                queue.append(contentsOf: filtered)
                originalQueue = queue
                load(filtered[0])
            } catch {
                pause()
            }
        }
    }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int) {
        clearSleepTimer()
        guard minutes > 0 else { return }
        sleepRemaining = minutes * 60
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.sleepRemaining -= 1
                if self.sleepRemaining <= 0 {
                    self.pause()
                    self.clearSleepTimer()
                }
            }
        }
    }

    func setSleepAtEndOfTrack() {
        sleepAtEndOfTrack = true
        sleepRemaining = -1
    }

    func clearSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepRemaining = 0
        sleepAtEndOfTrack = false
    }

    // MARK: Loading

    private func load(_ song: Song) {
        currentSong = song
        position = 0
        duration = Double(song.duration ?? 0)
        reResolveAttempted = false
        errorMessage = nil
        resolvedUrls.removeValue(forKey: song.id) // never reuse stale URLs across plays

        LibraryStore.shared.recordPlay(song)

        if song.isLocal {
            loadLocal(song)
        } else {
            loadRemote(song)
        }
        fetchArtworkColor(song)
    }

    private func loadLocal(_ song: Song) {
        guard let url = LibraryStore.shared.localFileUrl(for: song) else {
            errorMessage = "File is unavailable on this device"
            handleSkipAfterError()
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        configureAudioSession()
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    private func loadRemote(_ song: Song) {
        isBuffering = true
        player.replaceCurrentItem(with: nil)
        Task { @MainActor in
            do {
                let stream = try await InnerTube.shared.resolveStream(videoId: song.videoId)
                let item = AVPlayerItem(url: stream.url)
                player.replaceCurrentItem(with: item)
                configureAudioSession()
                player.play()
                isPlaying = true
                if let d = stream.duration, d > 0 {
                    duration = Double(d)
                }
                updateNowPlaying()
            } catch {
                isBuffering = false
                errorMessage = error.localizedDescription
                handleSkipAfterError()
            }
        }
    }

    /// Error-skip behavior — mirrors the Android "skip on error" player setting.
    private func handleSkipAfterError() {
        guard AppSettings.shared.skipOnStreamError else { return }
        let index = currentIndex
        if index >= 0 && index + 1 < queue.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                Task { @MainActor in
                    guard let self = self, self.errorMessage != nil else { return }
                    self.next()
                }
            }
        }
    }

    private func handleItemError() {
        guard let song = currentSong, !song.isLocal, !reResolveAttempted else {
            errorMessage = "Playback failed"
            handleSkipAfterError()
            return
        }
        reResolveAttempted = true
        // Stream URLs expire; resolve a fresh one.
        Task { @MainActor in
            do {
                let stream = try await InnerTube.shared.resolveStream(videoId: song.videoId)
                let item = AVPlayerItem(url: stream.url)
                player.replaceCurrentItem(with: item)
                player.play()
                isPlaying = true
            } catch {
                errorMessage = error.localizedDescription
                handleSkipAfterError()
            }
        }
    }

    // MARK: Periodic tick

    private func tick(_ time: CMTime) {
        guard player.currentItem != nil else { return }
        position = time.seconds
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        if !itemDuration.isNaN && itemDuration > 0 {
            duration = itemDuration
        }
        if Int(position) % 5 == 0 {
            updateNowPlaying()
        }
    }

    private func handleTrackEnded() {
        if repeatMode == .one {
            seek(to: 0)
            play()
        } else {
            next(auto: true)
        }
    }

    // MARK: Interruptions

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            pause()
        } else if type == .ended {
            if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                play()
            }
        }
    }

    // MARK: Now Playing / artwork

    private func updateNowPlaying(rate: Float? = nil) {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artistsText,
            MPMediaItemPropertyPlaybackDuration: max(duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(position, 0),
            MPNowPlayingInfoPropertyPlaybackRate: rate ?? (isPlaying ? 1.0 : 0.0),
        ]
        if let lastArtwork = lastArtwork {
            let artwork = MPMediaItemArtwork(boundsSize: lastArtwork.size) { _ in lastArtwork }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func fetchArtworkColor(_ song: Song) {
        artworkDominantColor = nil
        lastArtwork = nil
        guard let urlString = song.thumbnailUrl, let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            Task { @MainActor in
                guard let self = self, self.currentSong?.id == song.id else { return }
                self.lastArtwork = image
                if AppSettings.shared.dynamicTheme,
                   let dominant = ArtworkColorExtractor.dominantUIColor(from: image) {
                    self.artworkDominantColor = dominant
                }
                self.updateNowPlaying()
            }
        }.resume()
    }
}
