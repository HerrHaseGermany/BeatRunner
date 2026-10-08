import MusicKit
import SwiftUI

struct SongLibraryCard: View {
    @ObservedObject var store: SongPaceStore
    let suggestedBPM: Double?
    let suggestedSpeed: Double?
    @State private var showsAddSong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Meine Songs")
                    .font(.headline)
                Spacer()
                Button {
                    showsAddSong = true
                } label: {
                    Label("Song", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if store.songs.isEmpty {
                Text("Speichere Songs zusammen mit der Geschwindigkeit, die sich auf dem Laufband gut angefühlt hat.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.songs) { song in
                    Button {
                        store.activate(song)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: store.activeSongID == song.id ? "checkmark.circle.fill" : "music.note")
                                .foregroundStyle(store.activeSongID == song.id ? .green : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    if !song.artist.isEmpty { Text(song.artist) }
                                    if let bpm = song.bpm { Text("\(bpm, specifier: "%.0f") BPM") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(song.speed, specifier: "%.1f") km/h")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Löschen", role: .destructive) { store.delete(song) }
                    }

                    if song.id != store.songs.last?.id { Divider() }
                }

                Text("Tippe einen Song an, um seine gespeicherte Geschwindigkeit als Ziel zu verwenden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .sheet(isPresented: $showsAddSong) {
            AddSongView(
                store: store,
                suggestedBPM: suggestedBPM,
                suggestedSpeed: suggestedSpeed
            )
        }
    }
}

private struct AddSongView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SongPaceStore
    @State private var title = ""
    @State private var artist = ""
    @State private var bpmText: String
    @State private var speed: Double
    @State private var showsMusicPicker = false

    init(store: SongPaceStore, suggestedBPM: Double?, suggestedSpeed: Double?) {
        self.store = store
        self._bpmText = State(initialValue: suggestedBPM.map { String(format: "%.0f", $0) } ?? "")
        self._speed = State(initialValue: suggestedSpeed ?? 8.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    Button {
                        showsMusicPicker = true
                    } label: {
                        Label("Aus Apple Music auswählen", systemImage: "music.note.list")
                    }

                    TextField("Titel", text: $title)
                    TextField("Interpret (optional)", text: $artist)
                    TextField("BPM (optional)", text: $bpmText)
                        .keyboardType(.decimalPad)
                }

                Section("Gelaufene Geschwindigkeit") {
                    HStack {
                        Text(speed, format: .number.precision(.fractionLength(1)))
                            .font(.title2.monospacedDigit().bold())
                        Text("km/h")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $speed, in: 3...20, step: 0.1)
                }
            }
            .navigationTitle("Song speichern")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsMusicPicker) {
                MusicLibrarySongPicker { song in
                    title = song.title
                    artist = song.artistName
                    showsMusicPicker = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let normalized = bpmText.replacingOccurrences(of: ",", with: ".")
                        store.add(
                            title: title,
                            artist: artist,
                            bpm: Double(normalized),
                            speed: speed
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

@MainActor
private final class MusicLibrarySongPickerModel: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        message = nil

        let authorization = MusicAuthorization.currentStatus == .authorized
            ? MusicAuthorization.currentStatus
            : await MusicAuthorization.request()

        guard authorization == .authorized else {
            message = "Apple-Music-Zugriff wurde nicht erlaubt."
            isLoading = false
            return
        }

        do {
            var request = MusicLibraryRequest<Song>()
            request.limit = 100
            let response = try await request.response()
            var allSongs = response.items

            while allSongs.hasNextBatch,
                  let nextBatch = try await allSongs.nextBatch(limit: 100) {
                allSongs += nextBatch
            }

            songs = Array(allSongs).sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder == .orderedSame {
                    return $0.artistName.localizedStandardCompare($1.artistName) == .orderedAscending
                }
                return titleOrder == .orderedAscending
            }

            if songs.isEmpty {
                message = "In deiner Apple-Music-Mediathek wurden keine Songs gefunden."
            }
        } catch {
            message = "Mediathek konnte nicht geladen werden: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

private struct MusicLibrarySongPicker: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MusicLibrarySongPickerModel()
    @State private var searchText = ""
    let onSelect: (Song) -> Void

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return model.songs }
        return model.songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.artistName.localizedCaseInsensitiveContains(searchText)
                || ($0.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.songs.isEmpty {
                    ProgressView("Apple Music wird geladen …")
                } else {
                    List {
                        ForEach(filteredSongs) { song in
                            Button {
                                onSelect(song)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note")
                                        .frame(width: 38, height: 38)
                                        .background(Color.pink.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(.pink)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(song.artistName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if let message = model.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .refreshable { await model.load() }
                }
            }
            .navigationTitle("Song auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Titel, Interpret oder Album")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await model.load() }
    }
}
