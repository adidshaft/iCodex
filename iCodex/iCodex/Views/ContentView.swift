import SwiftUI

struct ContentView: View {
    @ObservedObject private var config = ServerConfig.shared
    private var themeManager = ThemeManager.shared
    @State private var pairingAlertMessage: String?
    @State private var pairingTask: Task<Void, Never>?
    @State private var bannerMessage: String?
    @State private var bannerIsError = false
    @State private var bannerDismissTask: Task<Void, Never>?

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
        .safeAreaInset(edge: .top) {
            if let bannerMessage {
                HStack(spacing: 10) {
                    Image(systemName: bannerIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(bannerMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bannerIsError ? Color.orange.opacity(0.92) : themeManager.current.accent.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: config.launchStatusMessage) {
            guard let message = config.consumeLaunchStatusMessage() else { return }
            let isError = !config.isAuthenticated
            await MainActor.run {
                showBanner(message, isError: isError)
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
                        config.applyAuthenticatedSession(host: request.host, port: request.port, apiKey: key)
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

    private func showBanner(_ message: String, isError: Bool) {
        bannerDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            bannerMessage = message
            bannerIsError = isError
        }
        bannerDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    bannerMessage = nil
                }
            }
        }
    }
}
