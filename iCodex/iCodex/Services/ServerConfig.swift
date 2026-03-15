import Foundation
import Combine

final class ServerConfig: ObservableObject {
    static let shared = ServerConfig()

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "server_host") }
    }
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "server_port") }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "server_api_key") }
    }

    var baseURL: String {
        "http://\(host):\(port)"
    }

    var isAuthenticated: Bool {
        !apiKey.isEmpty
    }

    private init() {
        let storedHost = UserDefaults.standard.string(forKey: "server_host") ?? ""
        let storedPort = UserDefaults.standard.integer(forKey: "server_port")
        let storedKey = UserDefaults.standard.string(forKey: "server_api_key") ?? ""
        self.host = storedHost
        self.port = storedPort == 0 ? 8642 : storedPort
        self.apiKey = storedKey
    }

    func clearAuth() {
        apiKey = ""
    }
}
