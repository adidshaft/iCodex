import SwiftUI

struct ContentView: View {
    @ObservedObject private var config = ServerConfig.shared
    private var themeManager = ThemeManager.shared
    @State private var pairingAlertMessage: String?
    @State private var pairingTask: Task<Void, Never>?

    var body: some View {
        Group {
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
        .task(id: config.pendingPairingRequest?.id) {
            guard let request = config.pendingPairingRequest else { return }
            pairingTask?.cancel()
            pairingTask = Task {
                do {
                    let key = try await APIService.shared.setupAuth(
                        host: request.host,
                        port: request.port,
                        passcode: request.passcode
                    )
                    await MainActor.run {
                        config.host = request.host
                        config.port = request.port
                        config.apiKey = key
                        config.pendingPairingRequest = nil
                        pairingAlertMessage = "Paired with \(request.displayHost)."
                    }
                } catch {
                    await MainActor.run {
                        config.pendingPairingRequest = nil
                        pairingAlertMessage = "Could not pair with \(request.displayHost). Check the QR code and make sure iCodex-Connect is running."
                    }
                }
            }
        }
        .alert(
            "QR Pairing",
            isPresented: Binding(
                get: { pairingAlertMessage != nil },
                set: { newValue in
                    if !newValue {
                        pairingAlertMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                pairingAlertMessage = nil
            }
        } message: {
            Text(pairingAlertMessage ?? "")
        }
    }
}
