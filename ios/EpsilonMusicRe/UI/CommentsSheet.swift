import SwiftUI

// MARK: - Comments sheet (CommentSheet.kt parity)

struct CommentsSheet: View {
    let videoId: String

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal

    @State private var comments: [CommentItem] = []
    @State private var continuation: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var expandedReplies: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    HStack { Spacer(); ProgressView().padding(.vertical, 60); Spacer() }
                } else if let error = errorText {
                    ErrorBanner(message: error, onRetry: { load() })
                        .padding(16)
                } else if comments.isEmpty {
                    EmptyPlaceholder(icon: "bubble.left.and.bubble.right", text: "No comments yet.")
                } else {
                    List {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment, isExpanded: expandedReplies.contains(comment.id)) {
                                toggleReplies(comment)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        if continuation != nil {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView().padding(.vertical, 14)
                                } else {
                                    Button("Load more") { loadMore() }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(pal.accent)
                                        .padding(.vertical, 10)
                                }
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .background(pal.background.ignoresSafeArea())
        }
        .presentationDetents([.large])
        .task { load() }
    }

    private func load() {
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                let page = try await InnerTube.shared.comments(videoId: videoId)
                comments = page.comments
                continuation = page.continuation
                isLoading = false
            } catch {
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadMore() {
        guard let token = continuation, !isLoadingMore else { return }
        isLoadingMore = true
        Task { @MainActor in
            if let page = try? await InnerTube.shared.commentContinuation(token) {
                comments.append(contentsOf: page.comments.filter { comment in
                    !comments.contains(where: { $0.commentId == comment.commentId })
                })
                continuation = page.continuation
            } else {
                continuation = nil
            }
            isLoadingMore = false
        }
    }

    private func toggleReplies(_ comment: CommentItem) {
        if expandedReplies.contains(comment.id) {
            expandedReplies.remove(comment.id)
        } else {
            expandedReplies.insert(comment.id)
            guard let token = comment.repliesToken, comment.replies.isEmpty else { return }
            Task { @MainActor in
                if let page = try? await InnerTube.shared.commentReplies(token) {
                    if let index = comments.firstIndex(where: { $0.commentId == comment.commentId }) {
                        comments[index].replies = page.comments
                    }
                }
            }
        }
    }
}

struct CommentRow: View {
    let comment: CommentItem
    let isExpanded: Bool
    let onToggleReplies: () -> Void

    @Environment(\.epsPalette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SongThumb(url: comment.avatar, size: 34, corner: 17, circle: true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(comment.author)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(pal.textSecondary)
                        Text(comment.publishedTime)
                            .font(.system(size: 12))
                            .foregroundStyle(pal.textSecondary.opacity(0.7))
                    }
                    Text(comment.text)
                        .font(.system(size: 14))
                        .foregroundStyle(pal.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Label(comment.likeCount.isEmpty ? "0" : comment.likeCount,
                              systemImage: comment.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 12))
                            .foregroundStyle(comment.isLiked ? pal.accent : pal.textSecondary)
                        if comment.replyCount > 0 {
                            Button {
                                onToggleReplies()
                            } label: {
                                Text(isExpanded ? "Hide replies (\(comment.replyCount))" : "\(comment.replyCount) replies")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(pal.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if isExpanded {
                ForEach(comment.replies) { reply in
                    HStack(alignment: .top, spacing: 8) {
                        SongThumb(url: reply.avatar, size: 24, corner: 12, circle: true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(reply.author)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(pal.textSecondary)
                                Text(reply.publishedTime)
                                    .font(.system(size: 11))
                                    .foregroundStyle(pal.textSecondary.opacity(0.7))
                            }
                            Text(reply.text)
                                .font(.system(size: 13))
                                .foregroundStyle(pal.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Queue sheet (Queue.kt parity — reorder + similar content)

struct QueueSheet: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epsPalette) private var pal

    @State private var similarSongs: [Song] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Header row: like + playing from + controls.
                    HStack(spacing: 10) {
                        if let song = player.currentSong {
                            Button {
                                library.toggleLike(song)
                            } label: {
                                Image(systemName: library.isLiked(song) ? "heart.fill" : "heart")
                                    .font(.system(size: 18))
                                    .foregroundStyle(library.isLiked(song) ? pal.accent : pal.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.queueSourceName.isEmpty ? "Queue" : player.queueSourceName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pal.textPrimary)
                                .lineLimit(1)
                            Text("\(player.queue.count) songs")
                                .font(.system(size: 12))
                                .foregroundStyle(pal.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Shuffle | Repeat | Radio (Android's connected toggles).
                    HStack(spacing: 8) {
                        queuePill(icon: player.shuffle ? "shuffle" : "shuffle", label: "Shuffle", isActive: player.shuffle) {
                            player.toggleShuffle()
                        }
                        queuePill(icon: repeatIcon, label: repeatLabel, isActive: player.repeatMode != .off) {
                            player.cycleRepeat()
                        }
                        if let song = player.currentSong {
                            queuePill(icon: "dot.radiowaves.left.and.right", label: "Radio", isActive: false) {
                                player.startRadio(for: song)
                            }
                        }
                        Spacer()
                        Button {
                            player.clearQueue(keepingCurrent: false)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(pal.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if player.queue.isEmpty {
                        EmptyPlaceholder(icon: "list.bullet", text: "Nothing playing.")
                    } else {
                        SectionHeader(title: "Continue playing",
                                      trailingText: totalQueueTime)
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                            QueueRow(song: song, isCurrent: player.currentSong?.id == song.id, index: index) {
                                player.playAt(index: index)
                            } onRemove: {
                                player.removeFromQueue(at: index)
                            }
                        }
                    }

                    if !similarSongs.isEmpty {
                        SectionHeader(title: "Similar content")
                        ForEach(Array(similarSongs.enumerated()), id: \.element.id) { _, song in
                            HStack(spacing: 12) {
                                SongThumb(url: song.thumbnailUrl, size: 44, corner: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(pal.textPrimary)
                                        .lineLimit(1)
                                    Text(song.artistsText)
                                        .font(.system(size: 12))
                                        .foregroundStyle(pal.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    player.playNext(song)
                                } label: {
                                    Image(systemName: "playlist.play")
                                        .font(.system(size: 17))
                                        .foregroundStyle(pal.textSecondary)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    player.addToQueue(song)
                                } label: {
                                    Image(systemName: "text.badge.plus")
                                        .font(.system(size: 16))
                                        .foregroundStyle(pal.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                    }
                    Color.clear.frame(height: 80)
                }
            }
            .background(pal.background.ignoresSafeArea())
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadSimilar()
        }
    }

    private var totalQueueTime: String? {
        let total = player.queue.compactMap(\.duration).reduce(0, +)
        return total > 0 ? formatDuration(total) : nil
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    private func queuePill(icon: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isActive ? pal.accent : pal.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isActive ? pal.accent.opacity(0.15) : pal.surface))
        }
        .buttonStyle(.plain)
    }

    private func loadSimilar() async {
        guard let song = player.currentSong, !song.isLocal else { return }
        if let radio = try? await InnerTube.shared.radio(videoId: song.videoId) {
            let filtered = radio.filter { item in
                !player.queue.contains(where: { $0.videoId == item.videoId }) && item.videoId != song.videoId
            }
            similarSongs = Array(filtered.prefix(10))
        }
    }
}

struct QueueRow: View {
    let song: Song
    let isCurrent: Bool
    let index: Int
    let onPlay: () -> Void
    let onRemove: () -> Void

    @Environment(\.epsPalette) private var pal

    var body: some View {
        HStack(spacing: 12) {
            SongThumb(url: song.thumbnailUrl, size: 44, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? pal.accent : pal.textPrimary)
                    .lineLimit(1)
                Text(song.artistsText)
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if isCurrent {
                EqualizerBars()
            } else if let duration = song.duration {
                Text(formatDuration(duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(pal.textSecondary)
            }
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(pal.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}

/// Tiny animated equalizer bars (Android "now playing" indicator).
struct EqualizerBars: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { bar in
                Capsule()
                    .fill(Color.primary.opacity(0.7))
                    .frame(width: 3, height: animate ? 16 : 5)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(bar) * 0.15),
                        value: animate)
            }
        }
        .onAppear { animate = true }
    }
}
