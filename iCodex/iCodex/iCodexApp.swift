import SwiftUI

@main
struct iCodexApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = ServerConfig.shared.handlePairingURL(url)
                }
        }
    }
}
