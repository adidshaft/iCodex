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
    @State private var isShowingQRScanner = false

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
            case .success(let message), .warning(let message):
                return message
            case .error(let message, _):
                return message
            }
        }

        var suggestion: String? {
            switch self {
            case .error(_, let suggestion):
                return suggestion
            default:
                return nil
            }
        }

        var color: Color {
            switch self {
            case .success:
                return .green
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }

        var icon: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.circle.fill"
            }
        }

        var title: String {
            switch self {
            case .success:
                return "Connection looks good"
            case .warning:
                return "Connected with warnings"
            case .error:
                return "Connection needs attention"
            }
        }
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(buildNumber))"
    }

    private var trimmedHost: String {
        config.host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isConnecting: Bool {
        if case .connecting = authStatus {
            return true
        }
        return false
    }

    private var connectionStatusTitle: String {
        if config.isAuthenticated {
            return "Paired and ready"
        }
        if isScanning {
            return "Scanning your network"
        }
        if isTesting {
            return "Checking your connector"
        }
        return "Finish pairing your Mac"
    }

    private var connectionStatusSubtitle: String {
        if config.isAuthenticated {
            return "Your iPhone is connected to iCodex-Connect and ready to manage Codex remotely."
        }
        if isScanning {
            return "Looking for iCodex-Connect instances on your local network."
        }
        return "Point the app at your Mac connector, then pair with a QR code or 6-digit passcode."
    }

    private var authStatusBanner: (title: String, message: String, color: Color, icon: String)? {
        switch authStatus {
        case .success(let message):
            return ("Paired successfully", message, .green, "checkmark.shield.fill")
        case .error(let message):
            return ("Pairing failed", message, .red, "xmark.shield.fill")
        default:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        overviewCard
                        connectionCard

                        if !discoveredServers.isEmpty {
                            discoveredServersCard
                        }

                        pairingCard
                        appearanceCard
                        aboutCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isShowingQRScanner) {
                PairingQRCodeScannerSheet(
                    onScannedCode: handleScannedPairingCode,
                    onScannerError: { message in
                        authStatus = .error(message)
                    }
                )
            }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill((config.isAuthenticated ? Color.green : themeManager.current.accent).opacity(0.14))
                        .frame(width: 54, height: 54)

                    Image(systemName: config.isAuthenticated ? "checkmark.shield.fill" : "iphone.and.arrow.forward")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(config.isAuthenticated ? Color.green : themeManager.current.accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(connectionStatusTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.current.textPrimary)

                    Text(connectionStatusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(themeManager.current.textSecondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                summaryPill(title: "Endpoint", value: trimmedHost.isEmpty ? "Not set" : "\(trimmedHost):\(config.port)")
                summaryPill(title: "Network", value: "Same Wi-Fi")
                summaryPill(title: "Status", value: config.isAuthenticated ? "Paired" : "Awaiting pairing")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(themeManager.current.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(themeManager.current.divider.opacity(0.8), lineWidth: 1)
        )
    }

    private var connectionCard: some View {
        SettingsSectionCard(
            theme: themeManager.current,
            icon: "network",
            title: "Connect to your Mac",
            subtitle: "Enter the Mac connector address directly or scan your local network to find it."
        ) {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    fieldCard(label: "Mac Host or IP", icon: "macbook.and.iphone", prompt: "192.168.1.24") {
                        TextField("192.168.1.24", text: $config.host)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .foregroundStyle(themeManager.current.textPrimary)
                    }

                    fieldCard(label: "Port", icon: "point.3.connected.trianglepath.dotted") {
                        TextField("8642", value: $config.port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(themeManager.current.textPrimary)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        scanNetwork()
                    } label: {
                        actionLabel(
                            title: isScanning ? scanProgress : "Scan Local Network",
                            subtitle: "Look for iCodex-Connect nearby",
                            icon: "dot.radiowaves.left.and.right",
                            emphasis: true,
                            loading: isScanning
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting || isScanning)

                    Button {
                        testConnection()
                    } label: {
                        actionLabel(
                            title: isTesting ? "Testing connection..." : "Test Connector",
                            subtitle: "Check whether this address is reachable",
                            icon: "checkmark.seal",
                            emphasis: false,
                            loading: isTesting
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting || isScanning)
                }

                if let result = testResult {
                    StatusBanner(
                        theme: themeManager.current,
                        title: result.title,
                        message: result.message,
                        suggestion: result.suggestion,
                        icon: result.icon,
                        color: result.color
                    )
                }
            }
        }
    }

    private var discoveredServersCard: some View {
        SettingsSectionCard(
            theme: themeManager.current,
            icon: "antenna.radiowaves.left.and.right",
            title: "Discovered Servers",
            subtitle: "Tap one of the nearby connectors to fill in the host automatically."
        ) {
            VStack(spacing: 12) {
                ForEach(discoveredServers) { server in
                    Button {
                        config.host = server.ip
                        testResult = .success("Selected \(server.ip) - v\(server.version)")
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(themeManager.current.inputBackground)
                                    .frame(width: 48, height: 48)

                                Image(systemName: config.host == server.ip ? "checkmark.circle.fill" : "desktopcomputer")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(config.host == server.ip ? Color.green : themeManager.current.textSecondary)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(server.hostname.isEmpty ? server.ip : server.hostname)
                                    .font(.headline)
                                    .foregroundStyle(themeManager.current.textPrimary)

                                Text("\(server.ip) • v\(server.version) • \(server.threads) threads")
                                    .font(.caption)
                                    .foregroundStyle(themeManager.current.textSecondary)
                            }

                            Spacer()

                            Text(config.host == server.ip ? "Selected" : "Use")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(config.host == server.ip ? Color.green : themeManager.current.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(themeManager.current.inputBackground)
                                )
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(themeManager.current.inputBackground.opacity(0.75))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pairingCard: some View {
        SettingsSectionCard(
            theme: themeManager.current,
            icon: "qrcode.viewfinder",
            title: "Pair your iPhone",
            subtitle: "Open iCodex-Connect from your Mac menu bar, then scan the pairing QR or enter the 6-digit passcode."
        ) {
            VStack(spacing: 14) {
                if config.isAuthenticated {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.12))
                                .frame(width: 50, height: 50)

                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.green)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("This iPhone is paired")
                                .font(.headline)
                                .foregroundStyle(themeManager.current.textPrimary)

                            Text("Your next thread refresh will use the stored API key from your Mac connector.")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.current.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(themeManager.current.inputBackground)
                    )

                    Button(role: .destructive) {
                        config.clearAuth()
                        authStatus = .idle
                        passcodeInput = ""
                    } label: {
                        actionLabel(
                            title: "Disconnect This iPhone",
                            subtitle: "Remove the stored pairing key and reconnect later if needed",
                            icon: "lock.open",
                            emphasis: false,
                            loading: false
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        isShowingQRScanner = true
                    } label: {
                        actionLabel(
                            title: "Scan Pairing QR",
                            subtitle: "Fastest option if your Mac can show the code",
                            icon: "qrcode.viewfinder",
                            emphasis: true,
                            loading: false
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Or enter the passcode manually")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(themeManager.current.textPrimary)

                        HStack(spacing: 12) {
                            TextField("000000", text: $passcodeInput)
                                .keyboardType(.numberPad)
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(themeManager.current.inputBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(themeManager.current.divider.opacity(0.8), lineWidth: 1)
                                )
                                .onChange(of: passcodeInput) { _, newValue in
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
                                VStack(spacing: 4) {
                                    if isConnecting {
                                        ProgressView()
                                            .tint(themeManager.current.background)
                                    } else {
                                        Text("Pair")
                                            .font(.headline)
                                        Text("Connect")
                                            .font(.caption)
                                    }
                                }
                                .frame(width: 88, height: 88)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(themeManager.current.accent)
                                )
                                .foregroundStyle(themeManager.current.background)
                            }
                            .buttonStyle(.plain)
                            .disabled(passcodeInput.count != 6 || isConnecting)
                            .opacity((passcodeInput.count == 6 && !isConnecting) ? 1 : 0.55)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(themeManager.current.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(themeManager.current.divider.opacity(0.8), lineWidth: 1)
                    )
                }

                if let status = authStatusBanner {
                    StatusBanner(
                        theme: themeManager.current,
                        title: status.title,
                        message: status.message,
                        suggestion: nil,
                        icon: status.icon,
                        color: status.color
                    )
                }
            }
        }
    }

    private var appearanceCard: some View {
        SettingsSectionCard(
            theme: themeManager.current,
            icon: "paintpalette",
            title: "Appearance",
            subtitle: "Choose the look that feels most readable when you are checking in quickly."
        ) {
            VStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            themeManager.selectedTheme = theme
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ThemePreviewSwatch(theme: theme.colors)
                                .frame(width: 56, height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            themeManager.selectedTheme == theme
                                                ? theme.colors.accent
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.current.textPrimary)
                                Text(theme.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(themeManager.current.textSecondary)
                            }

                            Spacer()

                            if themeManager.selectedTheme == theme {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(theme.colors.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(themeManager.current.inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var aboutCard: some View {
        SettingsSectionCard(
            theme: themeManager.current,
            icon: "info.circle",
            title: "About iCodex",
            subtitle: "A lightweight remote companion for Codex that works best when your Mac and iPhone are nearby."
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCodex")
                            .font(.headline)
                            .foregroundStyle(themeManager.current.textPrimary)
                        Text("Remote pilot for Codex")
                            .font(.caption)
                            .foregroundStyle(themeManager.current.textSecondary)
                        Text(appVersionText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(themeManager.current.textSecondary)
                    }

                    Spacer()
                }

                infoRow(title: "API Endpoint", value: config.baseURL)
                infoRow(title: "Connection", value: "Local Wi-Fi / LAN")

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    infoLinkRow(title: "Privacy Policy", icon: "hand.raised.fill")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SupportGuideView()
                } label: {
                    infoLinkRow(title: "Support Guide", icon: "questionmark.circle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(themeManager.current.textSecondary)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeManager.current.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(themeManager.current.inputBackground)
        )
    }

    private func fieldCard<Content: View>(
        label: String,
        icon: String,
        prompt: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.current.textSecondary)

            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(themeManager.current.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(themeManager.current.divider.opacity(0.8), lineWidth: 1)
                )

            if let prompt {
                Text(prompt)
                    .font(.caption2)
                    .foregroundStyle(themeManager.current.textSecondary.opacity(0.85))
            }
        }
    }

    private func actionLabel(
        title: String,
        subtitle: String,
        icon: String,
        emphasis: Bool,
        loading: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        emphasis
                            ? themeManager.current.accent.opacity(0.16)
                            : themeManager.current.inputBackground
                    )
                    .frame(width: 50, height: 50)

                if loading {
                    ProgressView()
                        .tint(emphasis ? themeManager.current.accent : themeManager.current.textSecondary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(emphasis ? themeManager.current.accent : themeManager.current.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.current.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(themeManager.current.textSecondary)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeManager.current.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(emphasis ? themeManager.current.surface : themeManager.current.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    emphasis ? themeManager.current.accent.opacity(0.35) : themeManager.current.divider.opacity(0.7),
                    lineWidth: 1
                )
        )
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(themeManager.current.textPrimary)

            Spacer(minLength: 12)

            Text(value)
                .font(.caption)
                .foregroundStyle(themeManager.current.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeManager.current.inputBackground)
        )
    }

    private func infoLinkRow(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(themeManager.current.accent)
                .frame(width: 20)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.current.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(themeManager.current.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeManager.current.inputBackground)
        )
    }

    // MARK: - Auth

    private func connectWithPasscode() {
        authStatus = .connecting
        Task {
            do {
                let key = try await APIService.shared.setupAuth(
                    host: trimmedHost,
                    port: config.port,
                    passcode: passcodeInput
                )
                await MainActor.run {
                    config.applyAuthenticatedSession(
                        host: trimmedHost,
                        port: config.port,
                        apiKey: key
                    )
                    authStatus = .success("Paired with \(trimmedHost.isEmpty ? "your Mac" : trimmedHost).")
                    passcodeInput = ""
                }
            } catch let error as APIError {
                await MainActor.run {
                    switch error {
                    case .httpError(401), .unauthorized:
                        authStatus = .error("Invalid passcode. Double-check the code shown by iCodex-Connect.")
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

    private func handleScannedPairingCode(_ code: String) {
        guard let request = PairingRequest.from(scannedValue: code) else {
            authStatus = .error("That QR code is not a valid iCodex pairing code.")
            return
        }

        config.host = request.host
        config.port = request.port
        passcodeInput = request.passcode
        authStatus = .connecting

        Task {
            do {
                let key = try await APIService.shared.setupAuth(
                    host: request.host,
                    port: request.port,
                    passcode: request.passcode
                )
                await MainActor.run {
                    config.applyAuthenticatedSession(host: request.host, port: request.port, apiKey: key)
                    authStatus = .success("Paired with \(request.displayHost).")
                    passcodeInput = ""
                }
            } catch {
                await MainActor.run {
                    authStatus = .error("Could not pair from the QR code. Make sure iCodex-Connect is running on your Mac.")
                }
            }
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let result: TestResult
            do {
                let status = try await APIService.shared.fetchHealth()
                let threads = status.stats?.activeThreads ?? 0
                let running = status.stats?.runningThreads ?? 0
                result = .success(
                    "Connected to v\(status.version), with \(threads) total threads and \(running) currently running. Uptime: \(status.formattedUptime)."
                )
            } catch let error as APIError {
                result = diagnoseAPIError(error)
            } catch let error as URLError {
                result = diagnoseURLError(error)
            } catch {
                result = .error(error.localizedDescription)
            }

            await MainActor.run {
                testResult = result
                isTesting = false
            }
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
                    let ip = allIPs[nextIndex]
                    nextIndex += 1
                    group.addTask { await self.probeServer(ip: ip, port: port) }
                }

                var scannedCount = 0
                for await result in group {
                    scannedCount += 1
                    if scannedCount % 25 == 0 || scannedCount == totalCount {
                        let pct = Int(Double(scannedCount) / Double(totalCount) * 100)
                        await MainActor.run {
                            scanProgress = "Scanning... \(pct)%"
                        }
                    }
                    if let server = result {
                        found.append(server)
                        await MainActor.run {
                            discoveredServers = found.sorted { $0.ip < $1.ip }
                        }
                    }
                    if nextIndex < allIPs.count {
                        let ip = allIPs[nextIndex]
                        nextIndex += 1
                        group.addTask { await self.probeServer(ip: ip, port: port) }
                    }
                }
            }

            await MainActor.run {
                discoveredServers = found.sorted { $0.ip < $1.ip }

                if found.isEmpty {
                    testResult = .error(
                        "No iCodex servers found on your network.",
                        suggestion: "Make sure iCodex-Connect is running on your Mac and both devices are on the same Wi-Fi."
                    )
                } else if found.count == 1, let server = found.first {
                    config.host = server.ip
                    testResult = .success("Found iCodex-Connect at \(server.ip) - v\(server.version).")
                } else {
                    testResult = .success("Found \(found.count) servers. Tap one to fill in the address.")
                }

                isScanning = false
                scanProgress = ""
            }
        }
    }

    private func getSubnetsToScan() -> [String] {
        WiFiHelper.subnetsToScan(currentHost: config.host)
    }

    private func probeServer(ip: String, port: Int) async -> DiscoveredServer? {
        guard let url = URL(string: "http://\(ip):\(port)/health") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        let ephemeral = URLSessionConfiguration.ephemeral
        ephemeral.timeoutIntervalForRequest = 1.5
        ephemeral.timeoutIntervalForResource = 2.0
        let session = URLSession(configuration: ephemeral)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "running" else {
                return nil
            }

            let version = json["version"] as? String ?? "?"
            let stats = json["stats"] as? [String: Any]
            let threads = stats?["active_threads"] as? Int ?? 0

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
                "Cannot connect to \(config.host):\(config.port).",
                suggestion: "Make sure iCodex-Connect is running, then try scanning the local network."
            )
        case .timedOut:
            return .error(
                "Connection timed out.",
                suggestion: "Check that both devices are on the same Wi-Fi network and that the IP address is correct."
            )
        case .notConnectedToInternet:
            return .error(
                "No network connection.",
                suggestion: "Connect to the same Wi-Fi network as your Mac."
            )
        case .cannotFindHost:
            return .error(
                "Host '\(config.host)' not found.",
                suggestion: "Use your Mac's IP address, or scan the network to find it automatically."
            )
        default:
            return .error(
                "Network error: \(error.localizedDescription)",
                suggestion: "Check your network connection and confirm the Mac connector is running."
            )
        }
    }

    private func diagnoseAPIError(_ error: APIError) -> TestResult {
        switch error {
        case .httpError(let code):
            switch code {
            case 503:
                return .warning(
                    "The connector is up, but Codex data is unavailable right now. Make sure Codex is installed and has been opened at least once."
                )
            case 500:
                return .warning(
                    "The connector returned an internal error. Check the logs in ~/Library/iCodex/logs/."
                )
            default:
                return .error("The server returned HTTP \(code).")
            }
        case .invalidResponse:
            return .error(
                "Received an unexpected response.",
                suggestion: "You may be connecting to a different service. Verify that port \(config.port) is correct."
            )
        case .unauthorized:
            return .error(
                "Authentication required.",
                suggestion: "Pair this iPhone using the passcode or QR from iCodex-Connect on your Mac."
            )
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let theme: ThemeColors
    let icon: String
    let title: String
    let subtitle: String
    let content: Content

    init(
        theme: ThemeColors,
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.inputBackground)
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.divider.opacity(0.8), lineWidth: 1)
        )
    }
}

private struct StatusBanner: View {
    let theme: ThemeColors
    let title: String
    let message: String
    let suggestion: String?
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }
}

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
