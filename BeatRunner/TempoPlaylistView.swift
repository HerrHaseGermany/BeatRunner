import SwiftUI

struct TempoPlaylistCard: View {
    @ObservedObject var songStore: SongPaceStore
    let suggestedSpeed: Double?
    @StateObject private var builder = MusicPlaylistBuilder()
    @AppStorage("playlistTargetSpeed") private var targetSpeed = 9.0
    @AppStorage("playlistSpeedTolerance") private var tolerance = 0.6

    private var matchingSongs: [SongPace] {
        songStore.songs
            .filter { abs($0.speed - targetSpeed) <= tolerance }
            .sorted { abs($0.speed - targetSpeed) < abs($1.speed - targetSpeed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Playlist nach Laufgeschwindigkeit", systemImage: "music.note.list")
                .font(.headline)

            VStack(spacing: 2) {
                Text("PLAYLIST FÜR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(targetSpeed, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("km/h")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Slider(value: $targetSpeed, in: 4...18, step: 0.1)

            if let suggestedSpeed,
               abs(suggestedSpeed - targetSpeed) >= 0.05 {
                Button {
                    targetSpeed = min(max(suggestedSpeed, 4), 18)
                } label: {
                    Label(
                        "Aktuelle Empfehlung (\(suggestedSpeed, specifier: "%.1f") km/h) übernehmen",
                        systemImage: "arrow.down.to.line"
                    )
                }
                .font(.subheadline)
            }

            HStack {
                Text("Toleranz")
                Slider(value: $tolerance, in: 0.2...1.5, step: 0.1)
                Text("±\(tolerance, specifier: "%.1f")")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            if matchingSongs.isEmpty {
                Text("Für diesen Geschwindigkeitsbereich ist noch kein Song kalibriert. Speichere nach einem Testlauf Songs mit ihrer passenden Geschwindigkeit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(matchingSongs) { song in
                        HStack {
                            Text(song.title)
                                .lineLimit(1)
                            Spacer()
                            Text("\(song.speed, specifier: "%.1f")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }

            Button {
                Task {
                    await builder.createPlaylist(from: matchingSongs, targetSpeed: targetSpeed)
                }
            } label: {
                Label(
                    matchingSongs.isEmpty
                        ? "Keine passenden Songs"
                        : "Apple-Music-Playlist mit \(matchingSongs.count) Song\(matchingSongs.count == 1 ? "" : "s") erstellen",
                    systemImage: "apple.logo"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(builder.isWorking || matchingSongs.isEmpty)

            if builder.canPlay {
                Button {
                    Task { await builder.play() }
                } label: {
                    Label("Erstellte Playlist abspielen", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let message = builder.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .onAppear {
            if let suggestedSpeed {
                targetSpeed = min(max(suggestedSpeed, 4), 18)
            }
        }
    }
}
