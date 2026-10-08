import Accelerate
import AVFoundation
import Foundation

final class MicrophoneBPMDetector: ObservableObject, @unchecked Sendable {
    @Published private(set) var bpm: Double?
    @Published private(set) var confidence = 0.0
    @Published private(set) var inputLevel = 0.0
    @Published private(set) var beatPulse = 0
    @Published private(set) var isListening = false
    @Published private(set) var status = "Bereit"

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "de.beatrunner.audio-analysis", qos: .userInitiated)
    private var energyFrames: [(time: TimeInterval, value: Double)] = []
    private var lastEstimateTime: TimeInterval = 0
    private var smoothedBPM: Double?
    private var fluxAverage = 0.0
    private var fluxHistory: [(time: TimeInterval, value: Double)] = []
    private var tempoHistory: [(time: TimeInterval, bpm: Double, confidence: Double)] = []
    private var lastOnsetTime: TimeInterval = 0
    private var analysisStartTime: TimeInterval = 0
    private var lastAudibleTime: TimeInterval = 0
    private var hasInputTap = false
    private var ownsAudioSession = false

    func toggle() {
        isListening ? stop() : requestPermissionAndStart()
    }

    func stop() {
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine.stop()
        releaseAudioSession()
        isListening = false
        status = "Analyse angehalten"
        inputLevel = 0
        analysisQueue.async { [weak self] in
            self?.energyFrames.removeAll(keepingCapacity: true)
        }
    }

    private func requestPermissionAndStart() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            start()
        case .denied:
            status = "Mikrofonzugriff fehlt – bitte in Einstellungen erlauben."
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.start()
                    } else {
                        self?.status = "Ohne Mikrofonzugriff ist keine Analyse möglich."
                    }
                }
            }
        @unknown default:
            status = "Mikrofonstatus konnte nicht ermittelt werden."
        }
    }

    private func start() {
        guard !engine.isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .defaultToSpeaker]
            )
            try session.setActive(true)
            ownsAudioSession = true

            // playAndRecord kann sonst auf den leisen Hörer-Ausgang wechseln.
            // Externe Ausgänge (AirPods, Bluetooth, AirPlay) bleiben unangetastet.
            if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
                try session.overrideOutputAudioPort(.speaker)
            }

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                status = "Kein Mikrofoneingang verfügbar."
                releaseAudioSession()
                return
            }

            analysisQueue.sync {
                energyFrames.removeAll(keepingCapacity: true)
                smoothedBPM = nil
                lastEstimateTime = 0
                fluxAverage = 0
                fluxHistory.removeAll(keepingCapacity: true)
                tempoHistory.removeAll(keepingCapacity: true)
                lastOnsetTime = 0
                analysisStartTime = ProcessInfo.processInfo.systemUptime
                lastAudibleTime = analysisStartTime
            }
            bpm = nil
            confidence = 0

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.consume(buffer)
            }
            hasInputTap = true

            engine.prepare()
            try engine.start()
            isListening = true
            status = "Höre zu …"
        } catch {
            if hasInputTap {
                engine.inputNode.removeTap(onBus: 0)
                hasInputTap = false
            }
            engine.stop()
            releaseAudioSession()
            status = "Audio konnte nicht gestartet werden: \(error.localizedDescription)"
            isListening = false
        }
    }

    private func releaseAudioSession() {
        guard ownsAudioSession else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            // Die Analyse ist trotzdem beendet. Beim nächsten Start wird die
            // Session neu konfiguriert; die UI soll deshalb bedienbar bleiben.
        }
        ownsAudioSession = false
    }

    nonisolated private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameCount))
        let decibels = 20 * log10(max(Double(rms), 0.000_001))
        let level = min(max((decibels + 60) / 48, 0), 1)
        let endTime = ProcessInfo.processInfo.systemUptime
        let sampleRate = buffer.format.sampleRate

        // Ein RMS-Wert pro 1024er Audiopuffer ist für stark komprimierte Musik
        // zu grob. Kleinere Fenster erhalten die kurzen Kick-/Snare-Impulse.
        let windowSize = 256
        var energies: [Double] = []
        energies.reserveCapacity((frameCount + windowSize - 1) / windowSize)
        var offset = 0
        while offset < frameCount {
            let length = min(windowSize, frameCount - offset)
            var windowRMS: Float = 0
            vDSP_rmsqv(channel.advanced(by: offset), 1, &windowRMS, vDSP_Length(length))
            energies.append(Double(windowRMS))
            offset += length
        }
        let startTime = endTime - Double(frameCount) / sampleRate

        analysisQueue.async { [weak self] in
            guard let self else { return }
            for (index, energy) in energies.enumerated() {
                let time = startTime + (Double(index) + 0.5) * Double(windowSize) / sampleRate
                self.appendEnergy(time: time, value: energy)
            }
            DispatchQueue.main.async { [weak self] in
                self?.inputLevel = level
            }
        }
    }

    nonisolated private func appendEnergy(time: TimeInterval, value: Double) {
        let logEnergy = log10(max(value, 0.000_001))
        let previousEnergy = energyFrames.last?.value ?? logEnergy
        let flux = max(0, logEnergy - previousEnergy)
        fluxAverage = fluxAverage * 0.94 + flux * 0.06
        fluxHistory.append((time, flux))
        fluxHistory.removeAll { time - $0.time > 1.5 }

        energyFrames.append((time, logEnergy))
        energyFrames.removeAll { time - $0.time > 12 }

        if value > 0.001_5 {
            lastAudibleTime = time
        }

        let fluxVariance = fluxHistory.reduce(0.0) {
            let difference = $1.value - fluxAverage
            return $0 + difference * difference
        } / Double(max(fluxHistory.count, 1))
        let onsetThreshold = max(0.018, fluxAverage + sqrt(fluxVariance) * 1.35)
        let minimumOnsetGap = smoothedBPM.map { max(0.16, (60 / $0) * 0.42) } ?? 0.18
        let isOnset = time - analysisStartTime > 0.35
            && flux > onsetThreshold
            && time - lastOnsetTime > minimumOnsetGap
        if isOnset {
            lastOnsetTime = time
        }

        if isOnset {
            DispatchQueue.main.async { [weak self] in
                self?.beatPulse += 1
            }
        }

        guard time - lastEstimateTime >= 0.45 else { return }
        lastEstimateTime = time
        let signalIsTooQuiet = time - lastAudibleTime > 1.5

        guard let result = BeatEstimator.estimate(from: energyFrames) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isListening, self.bpm == nil {
                    self.status = signalIsTooQuiet
                        ? "Signal sehr leise – iPhone näher an die Musik legen."
                        : "Sammle Rhythmus …"
                }
            }
            return
        }

        var measuredBPM = result.bpm
        if let previous = smoothedBPM {
            let octaveCandidates = [measuredBPM / 2, measuredBPM, measuredBPM * 2]
                .filter { BeatEstimator.tempoRange.contains($0) }
            measuredBPM = octaveCandidates.min(by: {
                abs($0 - previous) < abs($1 - previous)
            }) ?? measuredBPM
        }

        tempoHistory.append((time, measuredBPM, result.confidence))
        tempoHistory.removeAll { time - $0.time > 3.2 }

        let sortedTempos = tempoHistory.map(\.bpm).sorted()
        let median = sortedTempos[sortedTempos.count / 2]
        let inliers = tempoHistory.filter { abs($0.bpm - median) <= 4.0 }
        let support = Double(inliers.count) / Double(tempoHistory.count)

        guard inliers.count >= 3, support >= 0.6 else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isListening else { return }
                self.status = "Prüfe Tempo …"
                self.confidence = min(result.confidence * 0.55, 0.4)
            }
            return
        }

        let totalWeight = inliers.reduce(0.0) { $0 + max($1.confidence, 0.15) }
        let consensusBPM = inliers.reduce(0.0) {
            $0 + $1.bpm * max($1.confidence, 0.15)
        } / totalWeight
        let nextBPM = smoothedBPM.map { $0 * 0.78 + consensusBPM * 0.22 } ?? consensusBPM
        let consensusConfidence = min(
            inliers.map(\.confidence).reduce(0, +) / Double(inliers.count) * support,
            1
        )
        smoothedBPM = nextBPM

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bpm = nextBPM
            self.confidence = consensusConfidence
            self.status = consensusConfidence > 0.5 ? "Rhythmus erkannt" : "Tempo stabilisiert sich …"
        }
    }
}

enum BeatEstimator {
    static let tempoRange = 70.0...200.0

    struct Result {
        let bpm: Double
        let confidence: Double
    }

    static func estimate(from frames: [(time: TimeInterval, value: Double)]) -> Result? {
        guard frames.count >= 550,
              let first = frames.first,
              let last = frames.last,
              last.time - first.time >= 4.0 else { return nil }

        let averageStep = (last.time - first.time) / Double(frames.count - 1)
        guard averageStep > 0.005, averageStep < 0.1 else { return nil }

        // Kurze Impulse werden gegen einen langsam folgenden lokalen Pegel
        // ausgewertet. Dadurch funktionieren leise und stark komprimierte Songs
        // mit demselben Verfahren.
        var smoothed = [Double](repeating: frames[0].value, count: frames.count)
        for index in 1..<frames.count {
            smoothed[index] = smoothed[index - 1] * 0.55 + frames[index].value * 0.45
        }

        let slowAlpha = min(max(averageStep / 0.45, 0.01), 0.25)
        var localFloor = smoothed[0]
        var rawOnset = [Double](repeating: 0, count: frames.count)
        for index in 1..<frames.count {
            localFloor += (smoothed[index] - localFloor) * slowAlpha
            let rise = max(0, smoothed[index] - smoothed[index - 1])
            let aboveFloor = max(0, smoothed[index] - localFloor)
            rawOnset[index] = rise * 0.72 + aboveFloor * 0.28
        }

        // Adaptiver Schwellwert über ungefähr eine Sekunde entfernt Gesang und
        // länger stehende Instrumente aus der Onset-Hüllkurve.
        let thresholdWindow = max(8, Int(1.0 / averageStep))
        var onset = [Double](repeating: 0, count: frames.count)
        var runningSum = 0.0
        for index in rawOnset.indices {
            runningSum += rawOnset[index]
            if index >= thresholdWindow {
                runningSum -= rawOnset[index - thresholdWindow]
            }
            let count = min(index + 1, thresholdWindow)
            let localMean = runningSum / Double(count)
            onset[index] = max(0, rawOnset[index] - localMean * 1.12)
        }

        let signalPower = onset.reduce(0) { $0 + $1 * $1 }
        guard signalPower > 0.000_01 else { return nil }

        let minLag = max(2, Int((60 / tempoRange.upperBound) / averageStep))
        let maxLag = min(onset.count / 2, Int((60 / tempoRange.lowerBound) / averageStep))
        guard minLag < maxLag else { return nil }

        var candidates: [(lag: Int, score: Double)] = []
        for lag in minLag...maxLag {
            var numerator = 0.0
            var leftPower = 0.0
            var rightPower = 0.0
            for index in lag..<onset.count {
                let left = onset[index]
                let right = onset[index - lag]
                numerator += left * right
                leftPower += left * left
                rightPower += right * right
            }
            let normalized = numerator / max(sqrt(leftPower * rightPower), 0.000_001)
            candidates.append((lag, normalized))
        }

        let peaks = onsetPeaks(in: onset, step: averageStep)
        guard peaks.count >= 5 else { return nil }
        let intervalHistogram = tempoHistogram(from: peaks, onset: onset, step: averageStep)

        let maximumCorrelation = candidates.map(\.score).max() ?? 0
        let maximumHistogram = intervalHistogram.max() ?? 0
        let ranked = candidates.map { candidate -> (lag: Int, raw: Double, combined: Double) in
            let bpm = 60 / (Double(candidate.lag) * averageStep)
            let bin = min(max(Int(bpm.rounded()) - Int(tempoRange.lowerBound), 0), intervalHistogram.count - 1)
            let correlationPart = candidate.score / max(maximumCorrelation, 0.000_001)
            let intervalPart = intervalHistogram[bin] / max(maximumHistogram, 0.000_001)
            let combined = correlationPart * 0.68
                + intervalPart * 0.32
                + harmonicSupport(for: candidate.lag, in: candidates) * 0.18
            return (candidate.lag, candidate.score, combined)
        }

        guard let best = ranked.max(by: { $0.combined < $1.combined }) else { return nil }
        let neighboringScores = ranked
            .filter { abs($0.lag - best.lag) > 3 }
            .map(\.combined)
            .sorted(by: >)
        let runnerUp = neighboringScores.first ?? 0
        let separation = max(0, best.combined - runnerUp)
        let bpm = 60 / (Double(best.lag) * averageStep)
        let confidence = min(max(best.raw * 1.2 + separation * 1.4, 0), 1)

        guard bpm.isFinite, tempoRange.contains(bpm), best.raw > 0.045 else { return nil }
        return Result(bpm: bpm, confidence: confidence)
    }

    private static func onsetPeaks(in onset: [Double], step: Double) -> [Int] {
        let mean = onset.reduce(0, +) / Double(onset.count)
        let variance = onset.reduce(0.0) {
            let difference = $1 - mean
            return $0 + difference * difference
        } / Double(onset.count)
        let threshold = mean + sqrt(variance) * 0.45
        let minimumDistance = max(1, Int(0.14 / step))
        var peaks: [Int] = []

        for index in 1..<(onset.count - 1) where onset[index] >= threshold {
            guard onset[index] >= onset[index - 1], onset[index] > onset[index + 1] else { continue }
            if let previous = peaks.last, index - previous < minimumDistance {
                if onset[index] > onset[previous] { peaks[peaks.count - 1] = index }
            } else {
                peaks.append(index)
            }
        }
        return peaks
    }

    private static func tempoHistogram(
        from peaks: [Int],
        onset: [Double],
        step: Double
    ) -> [Double] {
        let firstTempo = Int(tempoRange.lowerBound)
        let lastTempo = Int(tempoRange.upperBound)
        var histogram = [Double](repeating: 0, count: lastTempo - firstTempo + 1)

        for rightIndex in peaks.indices {
            let leftBoundary = max(0, rightIndex - 6)
            guard leftBoundary < rightIndex else { continue }
            for leftIndex in leftBoundary..<rightIndex {
                let interval = Double(peaks[rightIndex] - peaks[leftIndex]) * step
                guard interval > 0 else { continue }
                var tempo = 60 / interval
                while tempo < tempoRange.lowerBound { tempo *= 2 }
                while tempo > tempoRange.upperBound { tempo /= 2 }
                guard tempoRange.contains(tempo) else { continue }

                let center = Int(tempo.rounded()) - firstTempo
                let distanceWeight = 1 / Double(rightIndex - leftIndex)
                let strength = sqrt(onset[peaks[leftIndex]] * onset[peaks[rightIndex]])
                for offset in -2...2 {
                    let bin = center + offset
                    guard histogram.indices.contains(bin) else { continue }
                    let kernel = exp(-0.5 * pow(Double(offset) / 1.2, 2))
                    histogram[bin] += strength * distanceWeight * kernel
                }
            }
        }
        return histogram
    }

    private static func harmonicSupport(
        for lag: Int,
        in candidates: [(lag: Int, score: Double)]
    ) -> Double {
        let base = candidates.first { $0.lag == lag }?.score ?? 0
        guard base > 0 else { return 0 }
        let doubleLag = candidates.first { abs($0.lag - lag * 2) <= 1 }?.score ?? 0
        let halfLag = candidates.first { abs($0.lag * 2 - lag) <= 1 }?.score ?? 0
        return min((doubleLag * 0.65 + halfLag * 0.35) / base, 1)
    }
}
