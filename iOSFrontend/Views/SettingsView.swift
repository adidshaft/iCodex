import SwiftUI

struct SettingsView: View {
    @ObservedObject private var config = ServerConfig.shared
    @State private var passcode: String = ""
    @State private var isPairing = false
    @State private var pairResult: String?
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Connection ────────────────────────────────────────
                Section("Server Connection") {
                    TextField("Host / IP", text: $config.host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $config.port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                // ── Pairing ──────────────────────────────────────────
                Section {
                    if config.isPaired {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                            Text("Device is paired")
                                .foregroundStyle(.primary)
                            Spacer()
                            Button("Re-pair") {
                                config.clearAuth()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter the 6-digit passcode shown on your Mac's iCodex menu bar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField("Passcode", text: $passcode)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .frame(maxWidth: 120)

                                Button {
                                    pair()
                                } label: {
                                    if isPairing {
                                        ProgressView()
                                    } else {
                                        Text("Pair")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(passcode.count != 6 || isPairing)
                            }
                        }

                        if let result = pairResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.contains("OK") ? .green : .red)
                        }
                    }
                } header: {
                    Text("Device Pairing")
                }

                // ── Test ─────────────────────────────────────────────
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("OK") ? .green : .red)
                    }
                }

                // ── Device Info ──────────────────────────────────────
                Section("Device") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Device Name", text: $config.deviceName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── About ────────────────────────────────────────────
                Section("About") {
                    HStack {
                        Text("API Endpoint")
                        Spacer()
                        Text(config.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("iCodex 2.1")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func pair() {
        isPairing = true
        pairResult = nil
        Task {
            do {
                let apiKey = try await APIService.shared.pairWithPasscode(passcode)
                config.apiKey = apiKey
                config.isPaired = true
                pairResult = "OK - Paired successfully!"
                passcode = ""
            } catch {
                pairResult = "Failed: \(error.localizedDescription)"
            }
            isPairing = false
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let status = try await APIService.shared.fetchHealth()
                let threads = status.stats?.activeThreads ?? 0
                testResult = "OK - v\(status.version), \(threads) threads, uptime \(status.formattedUptime)"

                // Also verify auth if paired
                if config.isPaired {
                    let authOk = try await APIService.shared.verifyAuth()
                    if !authOk {
                        testResult = (testResult ?? "") + " | Auth: FAILED (re-pair needed)"
                    }
                }
            } catch {
                testResult = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
