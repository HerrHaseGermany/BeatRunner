import SwiftUI

struct ContentView: View {
    @StateObject private var detector = MicrophoneBPMDetector()
    @StateObject private var heightProfile = HeightProfile()
    @StateObject private var songStore = SongPaceStore()
    @StateObject private var tapTempo = TapTempoDetector()
    @State private var beatScale = 1.0
    @AppStorage("heightCM") private var heightCM = 175.0
    @AppStorage("strideCorrection") private var strideCorrection = 1.0
    @AppStorage("cadenceMode") private var cadenceModeRaw = CadenceMode.automatic.rawValue
    private let watchBridge = WatchBridge.shared

    private var baseStrideLength: Double {
        // Referenzwert bei 10 km/h; das Empfehlungsmodell passt ihn danach
        // automatisch an die berechnete Geschwindigkeit an.
        heightCM / 100 * 0.60 * strideCorrection
    }

    private var cadenceMode: Binding<CadenceMode> {
        Binding(
            get: { CadenceMode(rawValue: cadenceModeRaw) ?? .automatic },
            set: { cadenceModeRaw = $0.rawValue }
        )
    }

    private var recommendation: RunningRecommendation? {
        guard let bpm = effectiveBPM else { return nil }
        return RunningRecommendation(
            bpm: bpm,
            baseStrideLength: baseStrideLength,
            mode: cadenceMode.wrappedValue
        )
    }

    private var effectiveBPM: Double? {
        if detector.isListening { return detector.bpm }
        if tapTempo.isTapping { return tapTempo.bpm }
        return detector.bpm
    }

    private var targetSpeed: Double? {
        // Sobald ein Tempo vorliegt, hat die Live-Berechnung Vorrang. Dadurch
        // reagieren km/h und Watch sofort auf Körpergröße, Schrittweitenregler
        // und Taktübersetzung. Der gespeicherte Song-Wert ist nur ein Fallback.
        recommendation?.speed ?? songStore.activeSong?.speed
    }

    private var usesSavedSongSpeed: Bool {
        recommendation == nil && songStore.activeSong != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    listeningCard
                    speedCard
                    TempoPlaylistCard(
                        songStore: songStore,
                        suggestedSpeed: targetSpeed
                    )
                    SongLibraryCard(
                        store: songStore,
                        suggestedBPM: effectiveBPM,
                        suggestedSpeed: recommendation?.speed
                    )
                    settingsCard
                    safetyNote
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("BeatRunner")
            .onChange(of: heightProfile.importedHeightCM) { _, newHeight in
                if let newHeight {
                    heightCM = newHeight
                }
            }
            .onChange(of: detector.bpm) { _, _ in syncWatch() }
            .onChange(of: tapTempo.bpm) { _, _ in syncWatch() }
            .onChange(of: detector.beatPulse) { _, _ in pulseBeat() }
            .onChange(of: tapTempo.tapCount) { _, _ in pulseBeat() }
            .onChange(of: heightCM) { _, _ in syncWatch() }
            .onChange(of: strideCorrection) { _, _ in syncWatch() }
            .onChange(of: cadenceModeRaw) { _, _ in syncWatch() }
            .onChange(of: songStore.activeSongID) { _, _ in syncWatch() }
        }
    }

    private var listeningCard: some View {
        VStack(spacing: 14) {
            Button {
                guard !detector.isListening else { return }
                tapTempo.tap()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(detector.isListening ? 0.18 : 0.13))
                        .frame(width: 116, height: 116)
                        .scaleEffect(beatScale * (1 + detector.inputLevel * 0.14))

                    Image(systemName: "waveform")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.green)
                        .scaleEffect(beatScale)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detector.isListening ? "Erkannter Beat" : "Beat tippen")
            .animation(.easeOut(duration: 0.09), value: detector.inputLevel)

            if let bpm = effectiveBPM {
                Text("\(bpm, specifier: "%.0f") BPM")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())

                ProgressView(value: detector.isListening ? detector.confidence : tapTempo.confidence)
                    .tint((detector.isListening ? detector.confidence : tapTempo.confidence) > 0.45 ? .green : .orange)
                    .accessibilityLabel("Erkennungssicherheit")
            } else {
                Text("– BPM")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(detector.isListening ? detector.status : tapTempo.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if detector.isListening {
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                    ProgressView(value: detector.inputLevel)
                        .tint(detector.inputLevel > 0.08 ? .green : .orange)
                }
                .accessibilityLabel("Mikrofonpegel")
            }

            Button {
                if !detector.isListening { tapTempo.reset() }
                detector.toggle()
            } label: {
                Label(
                    detector.isListening ? "Analyse stoppen" : "Analyse starten",
                    systemImage: detector.isListening ? "stop.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(detector.isListening ? .red : .blue)
        }
        .cardStyle()
    }

    private var speedCard: some View {
        VStack(spacing: 8) {
            Text(usesSavedSongSpeed ? "GESPEICHERTES SONG-ZIEL" : "EMPFOHLENE GESCHWINDIGKEIT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let speed = targetSpeed {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(speed, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                    Text("km/h")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if usesSavedSongSpeed, let song = songStore.activeSong {
                    HStack {
                        Text(song.title)
                            .lineLimit(1)
                        Button("Schätzung verwenden") { songStore.clearActiveSong() }
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if let recommendation {
                    Text("\(recommendation.cadence, specifier: "%.0f") Schritte/min · \(recommendation.strideLength, specifier: "%.2f") m/Schritt")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("– km/h")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Wird nach der BPM-Erkennung oder dem Eintappen berechnet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Deine Laufparameter")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Körpergröße")
                    Spacer()
                    Text("\(heightCM, specifier: "%.0f") cm")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $heightCM, in: 130...220, step: 1)

                Button {
                    Task { await heightProfile.importHeight() }
                } label: {
                    Label("Aus Apple Health übernehmen", systemImage: "heart.text.square")
                }
                .disabled(heightProfile.isLoading)

                if let message = heightProfile.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Basis-Schrittlänge bei 10 km/h")
                    Spacer()
                    Text("\(baseStrideLength, specifier: "%.2f") m")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $strideCorrection, in: 0.80...1.20, step: 0.01)
                Text("Persönliche Korrektur: \(Int((strideCorrection - 1) * 100)) %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Bei höherem Tempo verlängert BeatRunner den Schritt automatisch; bei niedrigerem Tempo wird er kürzer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Taktübersetzung")
                Picker("Taktübersetzung", selection: cadenceMode) {
                    ForEach(CadenceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("0,25× und 0,5× eignen sich, um bei schneller Musik mit jedem vierten oder zweiten Schlag zu laufen. Auto verdoppelt Songs unter 115 BPM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var safetyNote: some View {
        Label {
            Text("Die Geschwindigkeit ist eine Empfehlung. Passe das Laufband nur in kleinen Schritten an und nutze den Sicherheitsclip.")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func syncWatch() {
        guard let speed = targetSpeed else { return }
        let bpm = effectiveBPM ?? songStore.activeSong?.bpm
        let cadence = bpm.map { cadenceMode.wrappedValue.cadence(for: $0) }
        watchBridge.send(
            bpm: bpm,
            cadence: cadence,
            speed: speed
        )
    }

    private func pulseBeat() {
        withAnimation(.spring(response: 0.12, dampingFraction: 0.45)) {
            beatScale = 1.28
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.16)) {
                beatScale = 1
            }
        }
    }
}

extension View {
    func cardStyle() -> some View {
        padding(20)
            .frame(maxWidth: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    ContentView()
}
