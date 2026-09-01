import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Queue-based audio player with lock-screen / Control Center integration.
@MainActor
final class PlayerManager: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    var currentSong: Song? {
        guard let index = currentIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        configureRemoteCommands()
    }

    deinit {
        progressTimer?.invalidate()
    }

    // MARK: - Transport

    func playQueue(_ songs: [Song], startAt index: Int) {
        guard !songs.isEmpty, songs.indices.contains(index) else { return }
        queue = songs
        load(at: index, autoplay: true)
    }

    func playSong(_ song: Song, in songs: [Song]) {
        let list = songs.isEmpty ? [song] : songs
        if let index = list.firstIndex(where: { $0.id == song.id }) {
            playQueue(list, startAt: index)
        } else {
            playQueue([song], startAt: 0)
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func next() {
        guard let index = currentIndex else { return }
        if queue.indices.contains(index + 1) {
            load(at: index + 1, autoplay: true)
        }
    }

    func previous() {
        guard let index = currentIndex else { return }
        if let player, player.currentTime > 3 {
            seek(to: 0)
        } else if queue.indices.contains(index - 1) {
            load(at: index - 1, autoplay: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: Double) {
        guard let player else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        currentTime = clamped
        updateNowPlayingInfo()
    }

    // MARK: - Internals

    private func load(at index: Int, autoplay: Bool) {
        currentIndex = index
        let song = queue[index]
        guard let url = song.url else {
            stop()
            return
        }
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            player = audioPlayer
            audioPlayer.prepareToPlay()
            duration = audioPlayer.duration
            currentTime = 0
            if autoplay {
                audioPlayer.play()
                isPlaying = true
            } else {
                isPlaying = false
            }
            startTimer()
        } catch {
            player = nil
            duration = 0
            currentTime = 0
            isPlaying = false
        }
        updateNowPlayingInfo()
    }

    private func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func startTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        updateNowPlayingInfo()
        if isPlaying && !player.isPlaying {
            // Track finished -> advance the queue.
            if let index = currentIndex, queue.indices.contains(index + 1) {
                load(at: index + 1, autoplay: true)
            } else {
                isPlaying = false
            }
        }
    }

    // MARK: - Now Playing / Remote commands

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
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
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let image = song.artwork {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
