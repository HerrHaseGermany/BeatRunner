import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)

                if let speed = session.speed {
                    Text(speed, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                    Text("km/h")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        metric(value: session.bpm, label: "BPM")
                        metric(value: session.cadence, label: "SPM")
                    }
                } else {
                    Text("Bereit")
                        .font(.title2.bold())
                    Text("Starte die Analyse auf deinem iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func metric(value: Double?, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value ?? 0, format: .number.precision(.fractionLength(0)))
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchSessionModel())
}
