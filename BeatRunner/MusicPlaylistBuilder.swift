import Combine
import MusicKit

@MainActor
final class MusicPlaylistBuilder: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var canPlay = false
    @Published private(set) var message: String?

    private var resolvedSongs: [Song] = []

    func createPlaylist(from paces: [SongPace], targetSpeed: Double) async {
        guard !paces.isEmpty else {
            message = "Speichere zuerst passende Songs."
            return
        }

        isWorking = true
        canPlay = false
        message = "Verbinde mit Apple Music …"

        let authorization = await MusicAuthorization.request()
        guard authorization == .authorized else {
            message = "Apple-Music-Zugriff wurde nicht erlaubt."
            isWorking = false
            return
        }

        do {
            var matches: [Song] = []
            var knownIDs = Set<MusicItemID>()

            for pace in paces {
                let match = try await findSong(for: pace)
                guard let match,
                      knownIDs.insert(match.id).inserted else { continue }
                matches.append(match)
            }

            guard !matches.isEmpty else {
                message = "Keiner der gespeicherten Songs wurde im Apple-Music-Katalog gefunden."
                isWorking = false
                return
            }

            let speedText = String(format: "%.1f", targetSpeed).replacingOccurrences(of: ".", with: ",")
            _ = try await MusicLibrary.shared.createPlaylist(
                name: "BeatRunner · \(speedText) km/h",
                description: "Von BeatRunner aus deinen erprobten Laufgeschwindigkeiten erstellt.",
                authorDisplayName: "BeatRunner",
                items: matches
            )

            resolvedSongs = matches
            canPlay = true
            message = "Playlist mit \(matches.count) Song\(matches.count == 1 ? "" : "s") erstellt."
        } catch {
            message = "Playlist konnte nicht erstellt werden: \(error.localizedDescription)"
        }

        isWorking = false
    }

    private func findSong(for pace: SongPace) async throws -> Song? {
        let term = [pace.title, pace.artist]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Zuerst die persönliche Mediathek durchsuchen. Nur wenn der Titel dort
        // nicht gefunden wird, fällt BeatRunner auf den Apple-Music-Katalog zurück.
        var libraryRequest = MusicLibrarySearchRequest(term: term, types: [Song.self])
        libraryRequest.limit = 10
        let libraryResponse = try await libraryRequest.response()
        if let match = bestMatch(for: pace, in: Array(libraryResponse.songs)) {
            return match
        }

        var catalogRequest = MusicCatalogSearchRequest(term: term, types: [Song.self])
        catalogRequest.limit = 10
        let catalogResponse = try await catalogRequest.response()
        return bestMatch(for: pace, in: Array(catalogResponse.songs))
    }

    func play() async {
        guard !resolvedSongs.isEmpty else { return }
        do {
            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: resolvedSongs)
            try await player.play()
            message = "Wiedergabe läuft."
        } catch {
            message = "Wiedergabe konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    private func bestMatch(for pace: SongPace, in candidates: [Song]) -> Song? {
        let expectedTitle = normalized(pace.title)
        let expectedArtist = normalized(pace.artist)

        return candidates.max { left, right in
            matchScore(left, title: expectedTitle, artist: expectedArtist)
                < matchScore(right, title: expectedTitle, artist: expectedArtist)
        }
    }

    private func matchScore(_ song: Song, title: String, artist: String) -> Int {
        var score = normalized(song.title) == title ? 3 : 0
        if !artist.isEmpty, normalized(song.artistName).contains(artist) { score += 2 }
        return score
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
