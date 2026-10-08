import Foundation

struct SongPace: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var bpm: Double?
    var speed: Double
    var updatedAt: Date

    init(title: String, artist: String, bpm: Double?, speed: Double) {
        id = UUID()
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.speed = speed
        updatedAt = Date()
    }
}

@MainActor
final class SongPaceStore: ObservableObject {
    @Published private(set) var songs: [SongPace] = []
    @Published private(set) var activeSongID: UUID?

    private let songsKey = "savedSongPaces"
    private let activeSongKey = "activeSongPaceID"

    var activeSong: SongPace? {
        songs.first { $0.id == activeSongID }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: songsKey),
           let decoded = try? JSONDecoder().decode([SongPace].self, from: data) {
            songs = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let idString = UserDefaults.standard.string(forKey: activeSongKey) {
            activeSongID = UUID(uuidString: idString)
        }
    }

    func add(title: String, artist: String, bpm: Double?, speed: Double) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        let song = SongPace(
            title: cleanedTitle,
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            bpm: bpm,
            speed: speed
        )
        songs.insert(song, at: 0)
        activeSongID = song.id
        persist()
    }

    func activate(_ song: SongPace) {
        activeSongID = activeSongID == song.id ? nil : song.id
        persist()
    }

    func clearActiveSong() {
        activeSongID = nil
        persist()
    }

    func delete(_ song: SongPace) {
        songs.removeAll { $0.id == song.id }
        if activeSongID == song.id { activeSongID = nil }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(songs) {
            UserDefaults.standard.set(data, forKey: songsKey)
        }
        UserDefaults.standard.set(activeSongID?.uuidString, forKey: activeSongKey)
    }
}
