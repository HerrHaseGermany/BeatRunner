import Combine
import Foundation

@MainActor
final class TapTempoDetector: ObservableObject {
    @Published private(set) var bpm: Double?
    @Published private(set) var confidence = 0.0
    @Published private(set) var tapCount = 0
    @Published private(set) var isTapping = false

    private var timestamps: [TimeInterval] = []

    var status: String {
        switch tapCount {
        case 0: "Tippe den Beat auf der grünen Wellenform ein."
        case 1: "Weiter auf die Wellenform tippen …"
        default: "Manuelles Tempo aus \(tapCount) Taps"
        }
    }

    func tap() {
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = timestamps.last, now - previous > 2.5 {
            reset()
        }

        timestamps.append(now)
        if timestamps.count > 9 {
            timestamps.removeFirst(timestamps.count - 9)
        }
        tapCount += 1
        isTapping = true
        calculateBPM()
    }

    func reset() {
        timestamps.removeAll(keepingCapacity: true)
        bpm = nil
        confidence = 0
        tapCount = 0
        isTapping = false
    }

    private func calculateBPM() {
        guard timestamps.count >= 2 else { return }

        let intervals = zip(timestamps.dropFirst(), timestamps).map(-)
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let stableIntervals = intervals.filter { abs($0 - median) <= median * 0.35 }
        guard !stableIntervals.isEmpty else { return }

        let average = stableIntervals.reduce(0, +) / Double(stableIntervals.count)
        let estimate = 60 / average
        guard estimate >= 35, estimate <= 240 else { return }

        bpm = estimate
        confidence = min(Double(stableIntervals.count) / 5, 1)
    }
}
