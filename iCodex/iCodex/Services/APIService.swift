import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class APIService {
    static let shared = APIService()

    private var baseURL: String {
        ServerConfig.shared.baseURL
    }

    private var apiKey: String {
        ServerConfig.shared.apiKey
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Request Helpers

    private var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    /// Create a GET URLRequest with auth header attached.
    private func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            ServerConfig.shared.recordActivity()
        }
        request.setValue(deviceName, forHTTPHeaderField: "X-Device-Name")
        return request
    }

    /// Create a POST/PUT URLRequest with auth + JSON content type.
    private func authenticatedJSONRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            ServerConfig.shared.recordActivity()
        }
        request.setValue(deviceName, forHTTPHeaderField: "X-Device-Name")
        return request
    }

    // MARK: - Auth

    struct AuthSetupResponse: Codable {
        let apiKey: String
        let message: String

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
            case message
        }
    }

    struct AuthVerifyResponse: Codable {
        let authenticated: Bool
        let message: String
    }

    /// Exchange a 6-digit setup passcode for the API key.
    func setupAuth(passcode: String) async throws -> String {
        try await setupAuth(host: ServerConfig.shared.host, port: ServerConfig.shared.port, passcode: passcode)
    }

    func setupAuth(host: String, port: Int, passcode: String) async throws -> String {
        let url = URL(string: "http://\(host):\(port)/auth/setup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceName, forHTTPHeaderField: "X-Device-Name")

        struct SetupBody: Encodable {
            let passcode: String
            let device_name: String
        }
        request.httpBody = try JSONEncoder().encode(
            SetupBody(passcode: passcode, device_name: deviceName)
        )

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let authResponse = try decoder.decode(AuthSetupResponse.self, from: data)
        return authResponse.apiKey
    }

    /// Verify that the current API key is valid.
    func verifyAuth() async throws -> Bool {
        let url = URL(string: "\(baseURL)/auth/verify")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let result = try decoder.decode(AuthVerifyResponse.self, from: data)
        return result.authenticated
    }

    // MARK: - Health (no auth required)

    func fetchHealth() async throws -> ServerStatus {
        let url = URL(string: "\(baseURL)/health")!
        let (data, response) = try await session.data(from: url)
        try Self.validate(response)
        return try decoder.decode(ServerStatus.self, from: data)
    }

    // MARK: - Threads

    func fetchThreads(includeArchived: Bool = false, limit: Int = 50) async throws -> [CodexThread] {
        let archived = includeArchived ? "true" : "false"
        let url = URL(string: "\(baseURL)/threads?include_archived=\(archived)&limit=\(limit)")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode([CodexThread].self, from: data)
    }

    func fetchThreadDetail(_ threadId: String) async throws -> ThreadDetail {
        let url = URL(string: "\(baseURL)/threads/\(threadId)")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ThreadDetail.self, from: data)
    }

    func fetchThreadMessages(_ threadId: String) async throws -> [ConversationMessage] {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/messages")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode([ConversationMessage].self, from: data)
    }

    // MARK: - Models

    func fetchModels() async throws -> [CodexModel] {
        let url = URL(string: "\(baseURL)/models")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode([CodexModel].self, from: data)
    }

    // MARK: - Config

    func fetchConfig() async throws -> CodexConfig {
        let url = URL(string: "\(baseURL)/config")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(CodexConfig.self, from: data)
    }

    // MARK: - Reply

    struct ReplyResponse: Codable {
        let status: String
        let message: String?
        let threadId: String?
        let method: String?
        let pid: Int?

        enum CodingKeys: String, CodingKey {
            case status, message, method, pid
            case threadId = "thread_id"
        }

        var isError: Bool { status == "busy" || status == "gui_error" }
        var isSentToGui: Bool { status == "sent_to_gui" }
        var displayMessage: String { message ?? "Message sent." }
    }

    func replyToThread(_ threadId: String, message: String) async throws -> ReplyResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/reply")!
        var request = authenticatedJSONRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(["message": message])

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ReplyResponse.self, from: data)
    }

    // MARK: - New Task

    func execTask(prompt: String, cwd: String, model: String? = nil, fullAuto: Bool = false) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/tasks/exec")!
        var request = authenticatedJSONRequest(url: url, method: "POST")

        var body: [String: Any] = ["prompt": prompt, "cwd": cwd, "full_auto": fullAuto]
        if let model = model { body["model"] = model }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - Stop Task

    func stopTask(_ taskId: String) async throws {
        let url = URL(string: "\(baseURL)/tasks/\(taskId)/stop")!
        let request = authenticatedJSONRequest(url: url, method: "POST")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
    }

    struct ActionResponse: Codable {
        let status: String
        let message: String?
    }

    struct GUIControlsResponse: Codable {
        let status: String
        let message: String?
        let controls: [GUIControlOption]?
        let sessionState: GUIRemoteSession?
        let codexRunning: Bool?
        let remoteReady: Bool?
        let supportedActions: [String]?

        enum CodingKeys: String, CodingKey {
            case status, message, controls
            case sessionState = "session_state"
            case codexRunning = "codex_running"
            case remoteReady = "remote_ready"
            case supportedActions = "supported_actions"
        }
    }

    func stopThread(_ threadId: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/stop")!
        let request = authenticatedJSONRequest(url: url, method: "POST")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ActionResponse.self, from: data)
    }

    func interruptThread(_ threadId: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/interrupt")!
        let request = authenticatedJSONRequest(url: url, method: "POST")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ActionResponse.self, from: data)
    }

    func performGUIAction(_ threadId: String, action: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/gui-action")!
        var request = authenticatedJSONRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(["action": action])

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ActionResponse.self, from: data)
    }

    func fetchGUIControls(_ threadId: String) async throws -> GUIControlsResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/gui-controls")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(GUIControlsResponse.self, from: data)
    }

    func pressGUIControl(_ threadId: String, controlId: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/gui-control-press")!
        var request = authenticatedJSONRequest(url: url, method: "POST")
        request.httpBody = try JSONEncoder().encode(["control_id": controlId])

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ActionResponse.self, from: data)
    }

    // MARK: - Config Update

    func updateConfig(model: String? = nil, reasoningEffort: String? = nil) async throws -> CodexConfig {
        let url = URL(string: "\(baseURL)/config")!
        var request = authenticatedJSONRequest(url: url, method: "PUT")

        var body: [String: String] = [:]
        if let model = model { body["model"] = model }
        if let effort = reasoningEffort { body["model_reasoning_effort"] = effort }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(CodexConfig.self, from: data)
    }

    // MARK: - Stats

    func fetchStats() async throws -> ThreadStats {
        let url = URL(string: "\(baseURL)/stats")!
        let request = authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ThreadStats.self, from: data)
    }

    // MARK: - Validation

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(http.statusCode)
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(let code):
            return "HTTP error \(code)."
        case .unauthorized:
            return "Authentication required. Please enter your setup passcode in Settings."
        }
    }
}
