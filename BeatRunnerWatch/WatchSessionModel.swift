import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionModel: NSObject, ObservableObject {
    @Published private(set) var bpm: Double?
    @Published private(set) var cadence: Double?
    @Published private(set) var speed: Double?
    @Published private(set) var updatedAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
    }

    private func apply(_ payload: [String: Any]) {
        guard let speed = payload["speed"] as? Double else { return }

        bpm = payload["bpm"] as? Double
        cadence = payload["cadence"] as? Double
        self.speed = speed
        if let timestamp = payload["updatedAt"] as? TimeInterval {
            updatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            updatedAt = Date()
        }
    }
}

extension WatchSessionModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in self?.apply(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in self?.apply(applicationContext) }
    }
}
