import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(bpm: Double?, cadence: Double?, speed: Double) {
        guard WCSession.isSupported() else { return }
        var payload: [String: Any] = [
            "speed": speed,
            "updatedAt": Date().timeIntervalSince1970
        ]
        if let bpm { payload["bpm"] = bpm }
        if let cadence { payload["cadence"] = cadence }

        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            // Die iPhone-Anzeige bleibt die primäre Oberfläche. Die nächste
            // Schätzung versucht automatisch erneut, den Kontext zu senden.
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
