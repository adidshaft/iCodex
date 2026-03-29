import Foundation
import Combine

final class ServerConfig: ObservableObject {
    static let shared = ServerConfig()
    static let idleSessionTimeout: TimeInterval = 7 * 24 * 60 * 60

    private enum DefaultsKey {
        static let host = "server_host"
        static let port = "server_port"
        static let apiKey = "server_api_key"
        static let lastActiveAt = "server_last_active_at"
        static let lastAuthenticatedAt = "server_last_authenticated_at"
    }

    @Published var pendingPairingRequest: PairingRequest?
    @Published var launchStatusMessage: String?
    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: DefaultsKey.host) }
    }
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: DefaultsKey.port) }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: DefaultsKey.apiKey) }
    }

    var baseURL: String {
        "http://\(host):\(port)"
    }

    var isAuthenticated: Bool {
        !apiKey.isEmpty
    }

    private init() {
        let defaults = UserDefaults.standard
        let storedHost = defaults.string(forKey: DefaultsKey.host) ?? ""
        let storedPort = defaults.integer(forKey: DefaultsKey.port)
        let storedKey = defaults.string(forKey: DefaultsKey.apiKey) ?? ""
        self.host = storedHost
        self.port = storedPort == 0 ? 8642 : storedPort

        let lastActiveAt = defaults.double(forKey: DefaultsKey.lastActiveAt)
        let lastAuthenticatedAt = defaults.double(forKey: DefaultsKey.lastAuthenticatedAt)
        let lastSeen = max(lastActiveAt, lastAuthenticatedAt)
        let now = Date().timeIntervalSince1970
        let isExpired = !storedKey.isEmpty && lastSeen > 0 && now - lastSeen > Self.idleSessionTimeout

        if isExpired {
            self.apiKey = ""
            defaults.removeObject(forKey: DefaultsKey.apiKey)
            defaults.removeObject(forKey: DefaultsKey.lastActiveAt)
            defaults.removeObject(forKey: DefaultsKey.lastAuthenticatedAt)
            self.launchStatusMessage = "Saved pairing expired after 7 days of inactivity. Scan the pairing QR to reconnect."
        } else {
            self.apiKey = storedKey
            if !storedKey.isEmpty {
                self.launchStatusMessage = storedHost.isEmpty
                    ? "Connected using saved pairing."
                    : "Connected using saved pairing to \(storedHost):\(self.port)."
                recordActivity()
            }
        }
    }

    func clearAuth() {
        apiKey = ""
        pendingPairingRequest = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.apiKey)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastActiveAt)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastAuthenticatedAt)
    }

    func applyAuthenticatedSession(host: String, port: Int, apiKey: String) {
        self.host = host
        self.port = port
        self.apiKey = apiKey
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: DefaultsKey.lastAuthenticatedAt)
        UserDefaults.standard.set(now, forKey: DefaultsKey.lastActiveAt)
    }

    func recordActivity() {
        guard !apiKey.isEmpty else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastActiveAt)
    }

    func consumeLaunchStatusMessage() -> String? {
        let message = launchStatusMessage
        launchStatusMessage = nil
        return message
    }

    func queuePairingRequest(_ request: PairingRequest) {
        pendingPairingRequest = request
    }

    @discardableResult
    func handlePairingURL(_ url: URL) -> Bool {
        guard let request = PairingRequest.from(url: url) else {
            return false
        }
        queuePairingRequest(request)
        return true
    }
}
