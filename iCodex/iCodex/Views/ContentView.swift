import SwiftUI

struct ContentView: View {
    @ObservedObject private var config = ServerConfig.shared
    private var themeManager = ThemeManager.shared

    var body: some View {
        if config.isAuthenticated {
            TabView {
                DashboardView()
                    .tabItem {
                        Label("Threads", systemImage: "list.bullet")
                    }

                ModelsView()
                    .tabItem {
                        Label("Models", systemImage: "cpu")
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
