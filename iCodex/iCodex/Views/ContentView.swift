import SwiftUI

struct ContentView: View {
    @ObservedObject private var config = ServerConfig.shared
    private var themeManager = ThemeManager.shared

    var body: some View {
        if config.isAuthenticated {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("Threads", systemImage: "bubble.left.and.bubble.right.fill")
                    }

                ModelsView()
                    .tabItem {
                        Label("Models", systemImage: "cpu.fill")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .tint(themeManager.current.accent)
        } else {
            OnboardingView()
        }
    }
}
