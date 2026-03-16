import SwiftUI

struct SettingsView: View {
    @ObservedObject private var config = ServerConfig.shared
    private var themeManager = ThemeManager.shared
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var isScanning = false
    @State private var scanProgress: String = ""
    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var passcodeInput: String = ""
    @State private var authStatus: AuthStatus = .idle
    @State private var isVerifyingAuth = false

    struct DiscoveredServer: Identifiable {
        let id = UUID()
        let ip: String
        let version: String
        let hostname: String
        let threads: Int
    }

    enum AuthStatus {
        case idle
        case connecting
        case success(String)
        case error(String)
    }

    enum TestResult {
        case success(String)
        case warning(String)
        case error(String, suggestion: String? = nil)

        var message: String {
            switch self {
            case .success(let m), .warning(let m): return m
            case .error(let m, _): return m
            }
        }

        var suggestion: String? {
            switch self {
            case .error(_, let s): return s
            default: return nil
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Testing...")
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isTesting || isScanning)

                    Button {
                        scanNetwork()
                    } label: {
                        HStack {
                            Spacer()
                            if isScanning {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text(scanProgress)
                            } else {
                                Label("Scan Network", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isTesting || isScanning)

                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: result.icon)
                                    .foregroundStyle(result.color)
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(result.color)
                            }
                            if let suggestion = result.suggestion {
                                Label(suggestion, systemImage: "lightbulb")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Scan searches your local network for a running iCodex server.")
                }

                // Discovered servers list
                if !discoveredServers.isEmpty {
                    Section("Discovered Servers") {
                        ForEach(discoveredServers) { server in
                            Button {
                                config.host = server.ip
                                testResult = .success("Selected \(server.ip) - v\(server.version)")
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.ip)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 4) {
                                            Text("v\(server.version)")
                                            if !server.hostname.isEmpty {
                                                Text("- \(server.hostname)")
                                            }
                                            Text("- \(server.threads) threads")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if config.host == server.ip {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }

                // Authentication
                Section {
                    if config.isAuthenticated {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Authenticated")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                                Text("Device is paired with server")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isVerifyingAuth {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(role: .destructive) {
                            config.clearAuth()
                            authStatus = .idle
                            passcodeInput = ""
                        } label: {
                            HStack {
                                Spacer()
                                Label("Disconnect", systemImage: "lock.open")
                                Spacer()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter the 6-digit passcode from the iCodex-Connect menu bar on your Mac:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                TextField("000000", text: $passcodeInput)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 160)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(uiColor: .tertiarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color(uiColor: .systemGray4), lineWidth: 1)
                                    )
                                    .onChange(of: passcodeInput) { _, newValue in
                                        // Limit to 6 digits
                                        let filtered = newValue.filter { $0.isNumber }
                                        if filtered.count > 6 {
                                            passcodeInput = String(filtered.prefix(6))
                                        } else {
                                            passcodeInput = filtered
                                        }
                                    }

                                Button {
                                    connectWithPasscode()
                                } label: {
                                    if case .connecting = authStatus {
                                        ProgressView()
                                            .frame(width: 80)
                                    } else {
                                        Text("Connect")
                                            .fontWeight(.semibold)
                                            .frame(width: 80)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(passcodeInput.count != 6 || {
                                    if case .connecting = authStatus { return true }
                                    return false
                                }())
                            }
                        }
                        .padding(.vertical, 4)

                        switch authStatus {
                        case .success(let msg):
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        case .error(let msg):
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        default:
                            EmptyView()
                        }
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    if !config.isAuthenticated {
                        Text("Open the iCodex-Connect menu bar app on your Mac. The 6-digit passcode is shown in the dropdown menu.")
                    }
                }

                // Theme Picker
                Section("Appearance") {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                themeManager.selectedTheme = theme
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ThemePreviewSwatch(theme: theme.colors)
                                    .frame(width: 54, height: 38)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                themeManager.selectedTheme == theme
                                                    ? theme.colors.accent
                                                    : Color.clear,
                                                lineWidth: 2
                                            )
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Text(theme.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if themeManager.selectedTheme == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.colors.accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section {
                    // App identity banner
                    HStack(spacing: 14) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("iCodex")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("Remote pilot for Codex")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(appVersionText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 1)
                        }
                    }
                    .padding(.vertical, 6)

                    HStack {
                        Text("API Endpoint")
                        Spacer()
                        Text(config.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text("Local WiFi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    NavigationLink {
                        SupportGuideView()
                    } label: {
                        Label("Support Guide", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Auth

    private func connectWithPasscode() {
        authStatus = .connecting
        Task {
            do {
                let key = try await APIService.shared.setupAuth(passcode: passcodeInput)
                await MainActor.run {
                    config.apiKey = key
                    authStatus = .success("Paired successfully!")
                    passcodeInput = ""
                }
            } catch let error as APIError {
                await MainActor.run {
                    switch error {
                    case .httpError(401), .unauthorized:
                        authStatus = .error("Invalid passcode. Check the code on your Mac.")
                    default:
                        authStatus = .error(error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run {
                    authStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let status = try await APIService.shared.fetchHealth()
                let threads = status.stats?.activeThreads ?? 0
                let running = status.stats?.runningThreads ?? 0
                testResult = .success(
                    "Connected - v\(status.version), \(threads) threads (\(running) running), uptime \(status.formattedUptime)"
                )
            } catch let error as APIError {
                testResult = diagnoseAPIError(error)
            } catch let error as URLError {
                testResult = diagnoseURLError(error)
            } catch {
                testResult = .error(error.localizedDescription)
            }
            isTesting = false
        }
    }

    // MARK: - Network Scanning

    private static let maxConcurrentProbes = 50

    private func scanNetwork() {
        isScanning = true
        testResult = nil
        discoveredServers = []
        scanProgress = "Scanning..."

        Task {
            let subnets = getSubnetsToScan()
            let port = config.port
            var found: [DiscoveredServer] = []

            let allIPs: [String] = subnets.flatMap { subnet in
                (1...254).map { "\(subnet).\($0)" }
            } + ["127.0.0.1"]
            let totalCount = allIPs.count

            await withTaskGroup(of: DiscoveredServer?.self) { group in
                var nextIndex = 0
                let initialBatch = min(Self.maxConcurrentProbes, allIPs.count)
                for _ in 0..<initialBatch {
                    let ip = allIPs[nextIndex]; nextIndex += 1
                    group.addTask { await self.probeServer(ip: ip, port: port) }
                }

                var scannedCount = 0
                for await result in group {
                    scannedCount += 1
                    if scannedCount % 25 == 0 || scannedCount == totalCount {
                        let pct = Int(Double(scannedCount) / Double(totalCount) * 100)
                        await MainActor.run { scanProgress = "Scanning... \(pct)%" }
                    }
                    if let server = result {
                        found.append(server)
                        await MainActor.run {
                            discoveredServers = found.sorted { $0.ip < $1.ip }
                        }
                    }
                    if nextIndex < allIPs.count {
                        let ip = allIPs[nextIndex]; nextIndex += 1
                        group.addTask { await self.probeServer(ip: ip, port: port) }
                    }
                }
            }

            await MainActor.run {
                discoveredServers = found.sorted { $0.ip < $1.ip }

                if found.isEmpty {
                    testResult = .error(
                        "No iCodex servers found on your network.",
                        suggestion: "Make sure the server is running on your Mac and both devices are on the same WiFi."
                    )
                } else if found.count == 1, let server = found.first {
                    config.host = server.ip
                    testResult = .success("Found server at \(server.ip) - v\(server.version)")
                } else {
                    testResult = .success("Found \(found.count) servers. Tap one to select it.")
                }

                isScanning = false
                scanProgress = ""
            }
        }
    }

    private func getSubnetsToScan() -> [String] {
        return WiFiHelper.subnetsToScan(currentHost: config.host)
    }

    private func probeServer(ip: String, port: Int) async -> DiscoveredServer? {
        guard let url = URL(string: "http://\(ip):\(port)/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        let ephemeral = URLSessionConfiguration.ephemeral
        ephemeral.timeoutIntervalForRequest = 1.5
        ephemeral.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: ephemeral)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "running" else { return nil }

            let version = json["version"] as? String ?? "?"
            let stats = json["stats"] as? [String: Any]
            let threads = stats?["active_threads"] as? Int ?? 0

            // Try to get hostname from network-info
            var hostname = ""
            if let netURL = URL(string: "http://\(ip):\(port)/network-info") {
                var netReq = URLRequest(url: netURL)
                netReq.timeoutInterval = 1.0
                if let (netData, _) = try? await session.data(for: netReq),
                   let netJson = try? JSONSerialization.jsonObject(with: netData) as? [String: Any] {
                    hostname = netJson["hostname"] as? String ?? ""
                }
            }

            return DiscoveredServer(ip: ip, version: version, hostname: hostname, threads: threads)
        } catch {
            return nil
        }
    }

    // MARK: - Error Diagnosis

    private func diagnoseURLError(_ error: URLError) -> TestResult {
        switch error.code {
        case .cannotConnectToHost, .networkConnectionLost:
            return .error(
                "Cannot connect to \(config.host):\(config.port)",
                suggestion: "Is the iCodex server running? Try 'Scan Network' to find it automatically."
            )
        case .timedOut:
            return .error(
                "Connection timed out",
                suggestion: "Check that both devices are on the same WiFi network and the IP address is correct."
            )
        case .notConnectedToInternet:
            return .error(
                "No network connection",
                suggestion: "Connect to the same WiFi network as your Mac."
            )
        case .cannotFindHost:
            return .error(
                "Host '\(config.host)' not found",
                suggestion: "Use your Mac's IP address (e.g. 192.168.1.x). Try 'Scan Network' to find it."
            )
        default:
            return .error(
                "Network error: \(error.localizedDescription)",
                suggestion: "Check your network connection and server status."
            )
        }
    }

    private func diagnoseAPIError(_ error: APIError) -> TestResult {
        switch error {
        case .httpError(let code):
            switch code {
            case 503:
                return .warning(
                    "Server is running but Codex data unavailable (HTTP 503). Make sure Codex is installed and has been run at least once."
                )
            case 500:
                return .warning(
                    "Server internal error (HTTP 500). Check server logs at ~/Library/iCodex/logs/"
                )
            default:
                return .error("Server returned HTTP \(code)")
            }
        case .invalidResponse:
            return .error(
                "Invalid response from server",
                suggestion: "You may be connecting to a different service. Verify port \(config.port) is correct."
            )
        case .unauthorized:
            return .error(
                "Authentication required",
                suggestion: "Enter the setup passcode from your Mac's terminal in the Authentication section above."
            )
        }
    }
}

// MARK: - Theme Preview Swatch

struct ThemePreviewSwatch: View {
    let theme: ThemeColors

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(theme.background)
            .overlay {
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.bubbleUser)
                        .frame(width: 14, height: 10)
                        .offset(y: -4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.bubbleAssistant)
                        .frame(width: 18, height: 10)
                        .offset(y: 4)
                }
                .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.accent.opacity(0.4), lineWidth: 1.5)
            )
    }
}
