import Foundation

enum CadenceMode: String, CaseIterable, Identifiable {
    case quarter = "0,25×"
    case half = "0,5×"
    case automatic = "Auto"
    case single = "1×"
    case double = "2×"

    var id: Self { self }

    func cadence(for bpm: Double) -> Double {
        switch self {
        case .quarter:
            return bpm * 0.25
        case .half:
            return bpm * 0.5
        case .automatic:
            return bpm < 115 ? bpm * 2 : bpm
        case .single:
            return bpm
        case .double:
            return bpm * 2
        }
    }
}

struct RunningRecommendation {
    let bpm: Double
    let cadence: Double
    let strideLength: Double
    let speed: Double

    init(bpm: Double, baseStrideLength: Double, mode: CadenceMode) {
        self.bpm = bpm
        cadence = mode.cadence(for: bpm)

        // Die körpergrößenbasierte Schrittlänge gilt als Referenz bei 10 km/h.
        // Mit höherem Tempo wird sie moderat länger. Die Iteration löst die
        // wechselseitige Abhängigkeit von Tempo und Schrittlänge stabil auf.
        var estimatedSpeed = cadence * baseStrideLength * 0.06
        for _ in 0..<10 {
            let dynamicStride = Self.dynamicStrideLength(
                base: baseStrideLength,
                speed: estimatedSpeed
            )
            estimatedSpeed = cadence * dynamicStride * 0.06
        }

        speed = min(max(estimatedSpeed, 0), 25)
        strideLength = Self.dynamicStrideLength(base: baseStrideLength, speed: speed)
    }

    static func dynamicStrideLength(base: Double, speed: Double) -> Double {
        let speedRatio = max(speed, 4) / 10
        let speedFactor = min(max(pow(speedRatio, 0.35), 0.72), 1.35)
        return base * speedFactor
    }
}
