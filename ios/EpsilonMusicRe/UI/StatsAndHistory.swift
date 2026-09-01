import SwiftUI

// MARK: - Stats screen (StatsScreen.kt parity)

struct StatsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    @State private var period: StatsPeriod = .month
    @State private var showActivity = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "Stats", showBack: true) {
                    Button {
                        showActivity = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(pal.textSecondary)
                    }
                }

                SelectionChips(options: StatsPeriod.allCases.map { ($0, $0.rawValue) }, selection: $period)
                    .padding(.horizontal, 12)

                topSongsSection
                topArtistsSection
                topAlbumsSection
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .sheet(isPresented: $showActivity) {
            ActivityHistorySheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var filteredHistory: [HistoryEntry] {
        guard let days = period.days else { return library.history }
        let cutoff = Date().timeIntervalSince1970 - Double(days * 86400)
        return library.history.filter { $0.playedAt >= cutoff }
    }

    private var filteredPlayTimes: [String: Double] {
        guard let days = period.days else { return library.playTimes }
        let cutoff = Date().timeIntervalSince1970 - Double(days * 86400)
        var times: [String: Double] = [:]
        for entry in filteredHistory {
            times[entry.song.id, default: 0] += library.playTimes[entry.song.id] ?? 0
        }
        _ = cutoff
        return times
    }

    private var topSongs: [(song: Song, playTime: Double, playCount: Int)] {
        var songs: [String: Song] = [:]
        var counts: [String: Int] = [:]
        for entry in filteredHistory {
            songs[entry.song.id] = entry.song
            counts[entry.song.id, default: 0] += 1
        }
        return filteredPlayTimes
            .compactMap { id, time -> (Song, Double, Int)? in
                guard let song = songs[id], time > 0 else { return nil }
                return (song, time, counts[id] ?? 0)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(20)
            .map { (song: $0.0, playTime: $0.1, playCount: $0.2) }
    }

    private var topArtists: [(artist: String, playTime: Double, playCount: Int)] {
        var stats: [String: (Double, Int)] = [:]
        for entry in filteredHistory {
            for artist in entry.song.artists {
                stats[artist, default: (0, 0)].0 += filteredPlayTimes[entry.song.id] ?? 0
                stats[artist, default: (0, 0)].1 += 1
            }
        }
        return stats
            .filter { $0.value.0 > 0 }
            .sorted { $0.value.0 > $1.value.0 }
            .prefix(15)
            .map { (artist: $0.key, playTime: $0.value.0, playCount: $0.value.1) }
    }

    private var topAlbums: [(album: String, song: Song, playTime: Double)] {
        var stats: [String: (String, Song, Double)] = [:]
        for entry in filteredHistory {
            guard let album = entry.song.album else { continue }
            stats[album, default: (album, entry.song, 0)].2 += filteredPlayTimes[entry.song.id] ?? 0
        }
        return stats
            .filter { $0.value.2 > 0 }
            .sorted { $0.value.2 > $1.value.2 }
            .prefix(15)
            .map { (album: $0.value.0, song: $0.value.1, playTime: $0.value.2) }
    }

    @ViewBuilder
    private var topSongsSection: some View {
        if topSongs.isEmpty {
            EmptyPlaceholder(icon: "chart.bar", text: "Play some music to build your stats.")
                .padding(.top, 30)
        } else {
            SectionHeader(title: "Most played songs")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(topSongs.enumerated()), id: \.element.song.id) { index, entry in
                        statSongCard(rank: index + 1, song: entry.song,
                                      playTime: entry.playTime, playCount: entry.playCount)
                    }
                }
                .padding(.horizontal, 16)
            }
            Button {
                let songs = topSongs.map(\.song).shuffled()
                if let first = songs.first {
                    player.play(first, queue: songs, sourceName: "Shuffled stats")
                    player.shuffle = true
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(pal.accent))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func statSongCard(rank: Int, song: Song, playTime: Double, playCount: Int) -> some View {
        Button {
            player.play(song, queue: topSongs.map(\.song), sourceName: "Stats")
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    SongThumb(url: song.thumbnailUrl, size: 130, corner: 12)
                    Text("\(rank)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(6, 10)
                        .background(Capsule().fill(pal.accent))
                        .padding(6)
                }
                Text(song.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(pal.textPrimary)
                    .lineLimit(1)
                Text("\(playCount) times • \(formatListenTime(playTime))")
                    .font(.system(size: 11))
                    .foregroundStyle(pal.textSecondary)
            }
            .frame(width: 130)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var topArtistsSection: some View {
        if !topArtists.isEmpty {
            SectionHeader(title: "Most played artists")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(topArtists.enumerated()), id: \.element.artist) { index, entry in
                        statArtistCard(rank: index + 1, artist: entry.artist,
                                       playTime: entry.playTime, playCount: entry.playCount)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func statArtistCard(rank: Int, artist: String, playTime: Double, playCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(pal.accent)
            Text(artist)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
                .lineLimit(1)
            Text("\(playCount) plays • \(formatListenTime(playTime))")
                .font(.system(size: 11))
                .foregroundStyle(pal.textSecondary)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.surface))
    }

    @ViewBuilder
    private var topAlbumsSection: some View {
        if !topAlbums.isEmpty {
            SectionHeader(title: "Most played albums")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(topAlbums.enumerated()), id: \.element.album) { index, entry in
                        statAlbumCard(rank: index + 1, album: entry.album, song: entry.song, playTime: entry.playTime)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func statAlbumCard(rank: Int, album: String, song: Song, playTime: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                SongThumb(url: song.thumbnailUrl, size: 110, corner: 12)
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(5, 9)
                    .background(Capsule().fill(pal.accent))
                    .padding(5)
            }
            Text(album)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pal.textPrimary)
                .lineLimit(1)
            Text(formatListenTime(playTime))
                .font(.system(size: 11))
                .foregroundStyle(pal.textSecondary)
        }
        .frame(width: 110)
    }
}

// MARK: - Activity history sheet (ActivityHistory.kt parity)

struct ActivityHistorySheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.epsPalette) private var pal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SectionHeader(title: "Listening activity")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(value: formatListenTime(library.totalPlayTime), label: "Total time")
                        StatCard(value: "\(library.history.count)", label: "Plays")
                        StatCard(value: "\(uniqueSongs)", label: "Unique songs")
                        StatCard(value: "\(uniqueArtists)", label: "Artists")
                    }
                    .padding(.horizontal, 16)
                    Color.clear.frame(height: 40)
                }
            }
            .background(pal.background.ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var uniqueSongs: Int {
        Set(library.history.map(\.song.id)).count
    }

    private var uniqueArtists: Int {
        Set(library.history.flatMap { $0.song.artists }).count
    }
}

// MARK: - History screen (HistoryScreen.kt parity — local buckets + remote)

struct HistoryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerManager
    @Environment(\.epsPalette) private var pal

    enum Source: String, CaseIterable, Identifiable {
        case local = "LOCAL"
        case remote = "REMOTE"
        var id: String { rawValue }
    }

    @State private var source: Source = .local
    @State private var remoteShelves: [Shelf] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                NavigationTitleBar(title: "History", showBack: true) {
                    if source == .local {
                        Button {
                            library.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(pal.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                SelectionChips(options: Source.allCases.map { ($0, $0.rawValue) }, selection: $source)
                    .padding(.horizontal, 12)

                if source == .local {
                    localContent
                } else {
                    remoteContent
                }
                Color.clear.frame(height: 96)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .task(id: source) {
            if source == .remote, remoteShelves.isEmpty {
                isLoading = true
                remoteShelves = (try? await InnerTube.shared.musicHistory()) ?? []
                isLoading = false
            }
        }
    }

    private var localContent: some View {
        ForEach(buckets, id: \.title) { bucket in
            SectionHeader(title: bucket.title)
            ForEach(bucket.entries) { entry in
                SongRow(song: entry.song, isCurrent: player.currentSong?.id == entry.song.id) { tapped, _ in
                    player.play(tapped, queue: bucket.entries.map(\.song), sourceName: bucket.title)
                }
            }
        }
    }

    private var buckets: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: library.history) { entry -> String in
            let date = Date(timeIntervalSince1970: entry.playedAt)
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) { return "This week" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
        let order = ["Today", "Yesterday", "This week"]
        var out: [(String, [HistoryEntry])] = []
        for key in order {
            if let entries = grouped[key], !entries.isEmpty {
                out.append((key, dedupe(entries)))
            }
        }
        for (key, entries) in grouped where !order.contains(key) {
            out.append((key, dedupe(entries)))
        }
        return out
    }

    private func dedupe(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var seen: Set<String> = []
        var out: [HistoryEntry] = []
        for entry in entries where seen.insert(entry.song.id).inserted {
            out.append(entry)
        }
        return out
    }

    @ViewBuilder
    private var remoteContent: some View {
        if isLoading {
            HStack { Spacer(); ProgressView().padding(.vertical, 40); Spacer() }
        } else if remoteShelves.isEmpty {
            EmptyPlaceholder(icon: "cloud", text: "Sign in to see your YouTube Music history.")
        } else {
            ForEach(remoteShelves) { shelf in
                SectionHeader(title: shelf.title)
                ForEach(shelf.items) { item in
                    if case .song(let song) = item {
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id) { tapped, _ in
                            player.play(tapped, queue: shelf.items.compactMap { songItem -> Song? in
                                if case .song(let s) = songItem { return s }
                                return nil
                            }, sourceName: shelf.title)
                        }
                    }
                }
            }
        }
    }
}
