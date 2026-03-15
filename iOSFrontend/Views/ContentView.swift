import SwiftUI

struct ContentView: View {
    @ObservedObject private var config = ServerConfig.shared

    var body: some View {
        if config.isConfigured {
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
            .tint(.blue)
        } else {
            // Not paired yet — show setup flow
            SetupView()
        }
    }
}

// MARK: - First-time setup

struct SetupView: View {
    @ObservedObject private var config = ServerConfig.shared
    @State private var passcode = ""
    @State private var isPairing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "desktopcomputer.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("Connect to iCodex Server")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Enter your Mac's IP address and the 6-digit passcode shown in the iCodex menu bar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 16) {
                    HStack {
                        TextField("Server IP", text: $config.host)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text(":")
                        TextField("Port", value: $config.port, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)

                    TextField("6-digit Passcode", text: $passcode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.title3.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 80)
                }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 32)
                }

                Button {
                    pair()
                } label: {
                    if isPairing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Pair Device")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .disabled(passcode.count != 6 || isPairing || config.host.isEmpty)

                Spacer()
                Spacer()
            }
            .navigationTitle("iCodex Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pair() {
        isPairing = true
        error = nil
        Task {
            do {
                // First check server is reachable
                _ = try await APIService.shared.fetchHealth()

                // Exchange passcode
                let apiKey = try await APIService.shared.pairWithPasscode(passcode)
                config.apiKey = apiKey
                config.isPaired = true
            } catch {
                self.error = error.localizedDescription
            }
            isPairing = false
        }
    }
}
