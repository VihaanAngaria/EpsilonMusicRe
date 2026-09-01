import UIKit

struct Song: Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    let url: URL?
    let artwork: UIImage?
    let isDemo: Bool
}

extension Song: Equatable {
    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}

struct ArtistGroup: Identifiable {
    let name: String
    let songs: [Song]
    var id: String { name }
}
