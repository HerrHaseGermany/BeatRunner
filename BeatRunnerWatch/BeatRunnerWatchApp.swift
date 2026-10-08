import SwiftUI

@main
struct BeatRunnerWatchApp: App {
    @StateObject private var session = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(session)
        }
    }
}
