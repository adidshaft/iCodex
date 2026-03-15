import Foundation
import Combine
import UIKit

final class ServerConfig: ObservableObject {
    static let shared = ServerConfig()

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "server_host") }
    }
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "server_port") }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "api_key") }
    }
    @Published var isPaired: Bool {
        didSet { UserDefaults.standard.set(isPaired, forKey: "is_paired") }
    }
    @Published var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: "device_name") }
    }

    var baseURL: String {
        "http://\(host):\(port)"
    }

    var isConfigured: Bool {
        isPaired && !apiKey.isEmpty
    }

    private init() {
        self.host = UserDefaults.standard.string(forKey: "server_host") ?? "192.168.1.100"
        self.port = UserDefaults.standard.integer(forKey: "server_port")
        if self.port == 0 { self.port = 8642 }
        self.apiKey = UserDefaults.standard.string(forKey: "api_key") ?? ""
        self.isPaired = UserDefaults.standard.bool(forKey: "is_paired")
        self.deviceName = UserDefaults.standard.string(forKey: "device_name") ?? UIDevice.current.name
    }

    func clearAuth() {
        apiKey = ""
        isPaired = false
    }
}
