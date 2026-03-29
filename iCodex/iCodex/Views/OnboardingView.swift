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
    @State private var isShowingQRScanner = false

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
        ZStack {
            // Deep dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.10, blue: 0.20),
                    Color(red: 0.04, green: 0.06, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero/Logo
                    heroSection
                        .padding(.top, 56)
                        .padding(.bottom, 28)

                    // Step content card
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
                    .padding(.horizontal, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)

                    Spacer(minLength: 16)

                    // Manual config link
                    if step != .done && step != .authenticate && step != .scanning {
                        Button("Enter IP Manually") {
                            cancelScan()
                            withAnimation { step = .authenticate }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.vertical, 20)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingQRScanner) {
            PairingQRCodeScannerSheet(
                onScannedCode: handleScannedPairingCode,
                onScannerError: { message in
                    authError = message
                }
            )
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.07), Color.clear],
                            center: .center,
                            startRadius: 18,
                            endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("iCodex")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Remote pilot for Codex")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }

    // MARK: - Prerequisites

    private var prerequisitesView: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.94))
                    .font(.system(size: 15, weight: .semibold))
                Text("Before You Start")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Card
            VStack(spacing: 0) {
                prerequisiteRow(
                    number: "1",
                    icon: "desktopcomputer",
                    title: "Install iCodex-Connect",
                    detail: "Open the DMG and drag iCodex-Connect to Applications"
                )
                Divider().background(Color.white.opacity(0.08))
                prerequisiteRow(
                    number: "2",
                    icon: "hand.raised.fill",
                    title: "Grant Accessibility Permission",
                    detail: "On first launch click 'Open Settings' and add it"
                )
                Divider().background(Color.white.opacity(0.08))
                prerequisiteRow(
                    number: "3",
                    icon: "app.badge.checkmark",
                    title: "Open the Codex App",
                    detail: "The Codex desktop app must be running"
                )
                Divider().background(Color.white.opacity(0.08))
                prerequisiteRow(
                    number: "4",
                    icon: "wifi",
                    title: "Same WiFi Network",
                    detail: "iPhone and Mac must be on the same local network"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // CTA
            VStack(spacing: 12) {
                Button {
                    isShowingQRScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan Pairing QR")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.22, green: 0.47, blue: 0.96))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { step = .scanning }
                    startScan()
                } label: {
                    HStack(spacing: 8) {
                        Text("Find My Server")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        }
    }

    private func prerequisiteRow(number: String, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.22, green: 0.47, blue: 0.96).opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.94))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 2)
                    .frame(width: 80, height: 80)
                Circle()
                    .stroke(Color(red: 0.22, green: 0.47, blue: 0.96).opacity(0.5), lineWidth: 2)
                    .frame(width: 60, height: 60)
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(Color(red: 0.30, green: 0.78, blue: 0.94))
            }

            VStack(spacing: 10) {
                Text("Searching for iCodex")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let subnet = detectedSubnet {
                    Text("Scanning \(subnet).x")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .monospacedDigit()
                }
                Text("\(Int(scanProgress * 100))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.94))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - No Server

    private var noServerView: some View {
        VStack(spacing: 24) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(Color.orange)
                .padding(.bottom, 4)

            VStack(spacing: 6) {
                Text("Server Not Found")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Make sure iCodex-Connect is running on your Mac and both are on the same WiFi.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            if let wifiIP = WiFiHelper.getWiFiIPAddress() {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.caption)
                    Text("iPhone: \(wifiIP)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(Color.white.opacity(0.35))
            }

            VStack(spacing: 12) {
                Button {
                    isShowingQRScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan Pairing QR")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.22, green: 0.47, blue: 0.96))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { step = .scanning }
                    startScan()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Again")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.22, green: 0.47, blue: 0.96))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation { step = .authenticate }
                } label: {
                    Text("Enter IP Manually")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Server Found

    private var serverFoundView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
                Text("Server Found!")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            ForEach(discoveredServers) { server in
                Button {
                    config.host = server.ip
                    manualIP = server.ip
                    withAnimation { step = .authenticate }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 42, height: 42)
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.ip)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("v\(server.version) · \(server.threads) threads")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if discoveredServers.count > 1 {
                Text("Tap a server to connect")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }

    // MARK: - Authenticate

    private var authenticateView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.94))
                Text("Connect to Server")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Scan the pairing QR from your Mac, or enter your Mac's IP and the 6-digit passcode manually.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            Button {
                isShowingQRScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan Pairing QR")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Fields card
            VStack(spacing: 16) {
                // Server IP
                VStack(alignment: .leading, spacing: 6) {
                    Text("SERVER IP ADDRESS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .tracking(1)
                    TextField("e.g. 192.168.1.42", text: $manualIP)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                        .tint(Color(red: 0.30, green: 0.78, blue: 0.94))
                        .onAppear {
                            if manualIP.isEmpty { manualIP = config.host }
                        }
                        .onChange(of: manualIP) { _, newValue in
                            config.host = newValue
                        }
                    if let wifiIP = WiFiHelper.getWiFiIPAddress() {
                        Text("Your iPhone: \(wifiIP)")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.3))
                            .monospacedDigit()
                    }
                }

                // Passcode
                VStack(alignment: .leading, spacing: 6) {
                    Text("SETUP PASSCODE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .tracking(1)
                    TextField("000000", text: $passcodeInput)
                        .keyboardType(.numberPad)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    passcodeInput.count == 6
                                        ? Color(red: 0.30, green: 0.78, blue: 0.94).opacity(0.5)
                                        : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )
                        .foregroundStyle(.white)
                        .tint(Color(red: 0.30, green: 0.78, blue: 0.94))
                        .onChange(of: passcodeInput) { _, newValue in
                            let sanitized = String(newValue.filter(\.isNumber).prefix(6))
                            if sanitized != newValue { passcodeInput = sanitized }
                        }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            // Status
            if isAuthenticating {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color(red: 0.30, green: 0.78, blue: 0.94))
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            if let error = authError {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            // Connect button
            Button {
                authenticate()
            } label: {
                HStack(spacing: 8) {
                    if isAuthenticating {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Connect")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            passcodeInput.count == 6 && !manualIP.isEmpty && !isAuthenticating
                                ? Color(red: 0.22, green: 0.47, blue: 0.96)
                                : Color.white.opacity(0.1)
                        )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(passcodeInput.count != 6 || manualIP.isEmpty || isAuthenticating)
            .animation(.easeInOut(duration: 0.2), value: passcodeInput.count)
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
                let key = try await APIService.shared.setupAuth(
                    host: trimmedIP,
                    port: config.port,
                    passcode: passcodeInput
                )
                await MainActor.run {
                    config.applyAuthenticatedSession(host: trimmedIP, port: config.port, apiKey: key)
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

    private func handleScannedPairingCode(_ code: String) {
        guard let request = PairingRequest.from(scannedValue: code) else {
            authError = "That QR code is not a valid iCodex pairing code."
            return
        }

        manualIP = request.host
        config.host = request.host
        config.port = request.port
        passcodeInput = request.passcode
        authError = nil

        if step != .authenticate {
            withAnimation { step = .authenticate }
        }

        authenticateScannedPairing(request)
    }

    private func authenticateScannedPairing(_ request: PairingRequest) {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        authError = nil

        Task {
            do {
                let key = try await APIService.shared.setupAuth(
                    host: request.host,
                    port: request.port,
                    passcode: request.passcode
                )
                await MainActor.run {
                    config.applyAuthenticatedSession(host: request.host, port: request.port, apiKey: key)
                    isAuthenticating = false
                    step = .done
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = "Could not pair from the QR code. Make sure iCodex-Connect is running on your Mac."
                }
            }
        }
    }
}
