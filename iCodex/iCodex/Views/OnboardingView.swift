import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var config = ServerConfig.shared

    @State private var step: OnboardingStep = .prerequisites
    @State private var scanProgress: Double = 0
    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var passcodeInput: String = ""
    @State private var manualIP: String = ""
    @State private var authError: String?
    @State private var isAuthenticating = false
    @State private var detectedSubnet: String?
    @State private var scanTask: Task<Void, Never>?

    private static let maxConcurrentProbes = 50
    private static let probeTimeout: TimeInterval = 2.0
    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = probeTimeout
        configuration.timeoutIntervalForResource = probeTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    struct DiscoveredServer: Identifiable {
        let id = UUID()
        let ip: String
        let version: String
        let threads: Int
    }

    private struct ProbeOutcome {
        let server: DiscoveredServer?
    }

    enum OnboardingStep {
        case prerequisites
        case scanning
        case noServerFound
        case serverFound
        case authenticate
        case done
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)
                    Text("iCodex")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Remote pilot for Codex")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)

                // Step content
                Group {
                    switch step {
                    case .prerequisites:
                        prerequisitesView
                    case .scanning:
                        scanningView
                    case .noServerFound:
                        noServerView
                    case .serverFound:
                        serverFoundView
                    case .authenticate:
                        authenticateView
                    case .done:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 20)

                // Manual config link
                if step != .done && step != .authenticate {
                    Button("Enter IP Manually") {
                        cancelScan()
                        step = .authenticate
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Prerequisites

    private var prerequisitesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Before You Start")
                .font(.headline)

            Text("Make sure you've completed these steps on your Mac:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                prerequisiteRow(
                    number: "1",
                    icon: "desktopcomputer",
                    title: "Install iCodex-Connect",
                    detail: "Open the DMG and drag iCodex-Connect to Applications on your Mac"
                )
                prerequisiteRow(
                    number: "2",
                    icon: "hand.raised.fill",
                    title: "Grant Accessibility Permission",
                    detail: "iCodex-Connect will prompt you on first launch — click 'Open Settings' and add it"
                )
                prerequisiteRow(
                    number: "3",
                    icon: "app.badge.checkmark",
                    title: "Open the Codex App",
                    detail: "The Codex desktop app must be running for remote control"
                )
                prerequisiteRow(
                    number: "4",
                    icon: "wifi",
                    title: "Same WiFi Network",
                    detail: "Your iPhone and Mac must be on the same local network. iOS will also ask for Local Network access the first time you connect."
                )
            }
            .padding(.vertical, 8)

            Button {
                step = .scanning
                startScan()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    private func prerequisiteRow(number: String, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching for iCodex server on your network...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let subnet = detectedSubnet {
                Text("Scanning \(subnet).x ...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text("\(Int(scanProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    // MARK: - No Server

    private var noServerView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("No iCodex server found")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label("Make sure iCodex-Connect is running on your Mac", systemImage: "desktopcomputer")
                Label("Both devices must be on the same WiFi", systemImage: "wifi")
                if let wifiIP = WiFiHelper.getWiFiIPAddress() {
                    Label("Your iPhone IP: \(wifiIP)", systemImage: "iphone")
                } else {
                    Label("iPhone doesn't appear to be on WiFi", systemImage: "wifi.slash")
                        .foregroundStyle(.red)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button {
                step = .scanning
                startScan()
            } label: {
                Label("Scan Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Button {
                step = .authenticate
            } label: {
                Text("Enter IP Manually")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
    }

    // MARK: - Server Found

    private var serverFoundView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Server found!")
                .font(.headline)

            ForEach(discoveredServers) { server in
                Button {
                    config.host = server.ip
                    manualIP = server.ip
                    step = .authenticate
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.ip)
                                .font(.body)
                                .fontWeight(.medium)
                            Text("v\(server.version) - \(server.threads) threads")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }

            if discoveredServers.count > 1 {
                Text("Tap a server to connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Authenticate

    private var authenticateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Connect to Server")
                .font(.headline)

            Text("Enter your Mac's IP and the 6-digit passcode from the iCodex-Connect menu bar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Server IP field
            VStack(alignment: .leading, spacing: 4) {
                Text("Server IP Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. 192.168.1.42", text: $manualIP)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .onAppear {
                        // Pre-fill with whatever was found or configured
                        if manualIP.isEmpty {
                            manualIP = config.host
                        }
                    }
                    .onChange(of: manualIP) { _, newValue in
                        config.host = newValue
                    }

                if let wifiIP = WiFiHelper.getWiFiIPAddress() {
                    Text("Your iPhone is on: \(wifiIP)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Passcode field
            VStack(alignment: .leading, spacing: 4) {
                Text("Setup Passcode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("000000", text: $passcodeInput)
                    .keyboardType(.numberPad)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .onChange(of: passcodeInput) { _, newValue in
                        let sanitized = String(newValue.filter(\.isNumber).prefix(6))
                        if sanitized != newValue {
                            passcodeInput = sanitized
                        }
                    }
            }

            if isAuthenticating {
                ProgressView("Connecting...")
            }

            if let error = authError {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                authenticate()
            } label: {
                Text("Connect")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(passcodeInput.count != 6 || manualIP.isEmpty || isAuthenticating)
        }
    }

    // MARK: - Actions

    private func startScan() {
        cancelScan()
        scanProgress = 0
        discoveredServers = []

        // Show the user which subnet we're actually scanning
        if let wifiIP = WiFiHelper.getWiFiIPAddress(),
           let subnet = WiFiHelper.subnetPrefix(from: wifiIP) {
            detectedSubnet = subnet
        }

        scanTask = Task {
            let port = config.port
            var found: [DiscoveredServer] = []
            var seenIPs = Set<String>()

            // Use WiFiHelper to get the device's actual WiFi subnet + fallbacks
            let subnets = WiFiHelper.subnetsToScan(currentHost: config.host)
            let totalTargets = (subnets.count * 254) + 1
            var completedTargets = 0

            for subnet in subnets {
                if Task.isCancelled { return }

                await MainActor.run {
                    detectedSubnet = subnet
                }

                let ips = (1...254).map { "\(subnet).\($0)" }
                let (servers, scannedTargets) = await scanSubnet(
                    ips,
                    port: port,
                    completedTargets: completedTargets,
                    totalTargets: totalTargets
                )
                completedTargets += scannedTargets

                for server in servers where seenIPs.insert(server.ip).inserted {
                    found.append(server)
                }

                if !found.isEmpty {
                    break
                }
            }

            if found.isEmpty, !Task.isCancelled {
                await MainActor.run {
                    detectedSubnet = "127.0.0"
                }
                if let localhostServer = await probe(ip: "127.0.0.1", port: port),
                   seenIPs.insert(localhostServer.ip).inserted {
                    found.append(localhostServer)
                }
                completedTargets = totalTargets
            }

            if Task.isCancelled { return }

            await MainActor.run {
                scanProgress = 1.0
                discoveredServers = found.sorted { $0.ip < $1.ip }
                scanTask = nil

                if found.isEmpty {
                    step = .noServerFound
                } else if found.count == 1, let server = found.first {
                    config.host = server.ip
                    manualIP = server.ip
                    step = .authenticate
                } else {
                    step = .serverFound
                }
            }
        }
    }

    private func scanSubnet(
        _ ips: [String],
        port: Int,
        completedTargets: Int,
        totalTargets: Int
    ) async -> ([DiscoveredServer], Int) {
        guard !ips.isEmpty else { return ([], 0) }

        let initialBatchSize = min(Self.maxConcurrentProbes, ips.count)

        return await withTaskGroup(of: ProbeOutcome.self, returning: ([DiscoveredServer], Int).self) { group in
            var nextIndex = 0
            for _ in 0..<initialBatchSize {
                let ip = ips[nextIndex]
                nextIndex += 1
                group.addTask {
                    ProbeOutcome(server: await probe(ip: ip, port: port))
                }
            }

            var found: [DiscoveredServer] = []
            var seenIPs = Set<String>()
            var scannedTargets = 0

            while let outcome = await group.next() {
                scannedTargets += 1

                if scannedTargets % 10 == 0 || scannedTargets == ips.count {
                    let progress = Double(completedTargets + scannedTargets) / Double(totalTargets)
                    await MainActor.run {
                        scanProgress = progress
                    }
                }

                if let server = outcome.server, seenIPs.insert(server.ip).inserted {
                    found.append(server)
                }

                if nextIndex < ips.count, !Task.isCancelled {
                    let ip = ips[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        ProbeOutcome(server: await probe(ip: ip, port: port))
                    }
                }
            }

            return (found, scannedTargets)
        }
    }

    private func probe(ip: String, port: Int) async -> DiscoveredServer? {
        guard let url = URL(string: "http://\(ip):\(port)/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.probeTimeout

        do {
            let (data, response) = try await Self.probeSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "running" else { return nil }

            let version = json["version"] as? String ?? "?"
            let stats = json["stats"] as? [String: Any]
            let threads = stats?["active_threads"] as? Int ?? 0
            return DiscoveredServer(ip: ip, version: version, threads: threads)
        } catch {
            return nil
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func authenticate() {
        guard passcodeInput.count == 6, !isAuthenticating else { return }

        // Ensure the host is set from the manual field
        let trimmedIP = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIP.isEmpty else {
            authError = "Please enter your Mac's IP address."
            return
        }
        config.host = trimmedIP

        isAuthenticating = true
        authError = nil

        Task {
            do {
                let key = try await APIService.shared.setupAuth(passcode: passcodeInput)
                await MainActor.run {
                    config.apiKey = key
                    isAuthenticating = false
                    step = .done
                }
            } catch let error as URLError {
                await MainActor.run {
                    isAuthenticating = false
                    passcodeInput = ""
                    switch error.code {
                    case .cannotConnectToHost, .timedOut:
                        authError = "Cannot reach \(config.host):\(config.port). Check the IP address and make sure iCodex-Connect is running."
                    case .cannotFindHost:
                        authError = "Host '\(config.host)' not found. Use an IP address like 192.168.x.x."
                    default:
                        authError = "Network error: \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = "Invalid passcode or connection failed. Check the code on your Mac."
                    passcodeInput = ""
                }
            }
        }
    }
}
