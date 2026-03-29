import SwiftUI

@main
struct iCodexApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = ServerConfig.shared.handlePairingURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        ServerConfig.shared.recordActivity()
                    }
                }
        }
    }
}
