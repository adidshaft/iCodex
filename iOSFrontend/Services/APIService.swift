import Foundation

final class APIService {
    static let shared = APIService()

    private var baseURL: String {
        ServerConfig.shared.baseURL
    }

    private var authToken: String {
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

    // MARK: - Auth

    /// Build a URLRequest with Bearer token and device name.
    private func authorizedRequest(_ url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !authToken.isEmpty {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        req.setValue(ServerConfig.shared.deviceName, forHTTPHeaderField: "X-Device-Name")
        return req
    }

    /// Exchange passcode for API key.
    func pairWithPasscode(_ passcode: String) async throws -> String {
        let url = URL(string: "\(baseURL)/auth/setup")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ServerConfig.shared.deviceName, forHTTPHeaderField: "X-Device-Name")

        struct PairBody: Encodable {
            let passcode: String
            let device_name: String
        }
        req.httpBody = try JSONEncoder().encode(
            PairBody(passcode: passcode, device_name: ServerConfig.shared.deviceName)
        )

        let (data, response) = try await session.data(for: req)
        try Self.validate(response)

        struct PairResponse: Decodable {
            let api_key: String
        }
        let parsed = try decoder.decode(PairResponse.self, from: data)
        return parsed.api_key
    }

    /// Verify current token is still valid.
    func verifyAuth() async throws -> Bool {
        let url = URL(string: "\(baseURL)/auth/verify")!
        let req = authorizedRequest(url)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Health (no auth needed)

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
        let req = authorizedRequest(url)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode([CodexThread].self, from: data)
    }

    func fetchThreadDetail(_ threadId: String) async throws -> ThreadDetail {
        let url = URL(string: "\(baseURL)/threads/\(threadId)")!
        let req = authorizedRequest(url)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(ThreadDetail.self, from: data)
    }

    func fetchThreadMessages(_ threadId: String) async throws -> [ConversationMessage] {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/messages")!
        let req = authorizedRequest(url)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode([ConversationMessage].self, from: data)
    }

    // MARK: - Reply

    func replyToThread(_ threadId: String, message: String) async throws -> ReplyResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/reply")!
        var req = authorizedRequest(url, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["message": message])

        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(ReplyResponse.self, from: data)
    }

    // MARK: - Stop / Interrupt

    func stopThread(_ threadId: String) async throws -> ThreadActionResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/stop")!
        let req = authorizedRequest(url, method: "POST")
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(ThreadActionResponse.self, from: data)
    }

    func interruptThread(_ threadId: String) async throws -> ThreadActionResponse {
        let url = URL(string: "\(baseURL)/threads/\(threadId)/interrupt")!
        let req = authorizedRequest(url, method: "POST")
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(ThreadActionResponse.self, from: data)
    }

    // MARK: - Models

    func fetchModels() async throws -> [CodexModel] {
        let url = URL(string: "\(baseURL)/models")!
        let req = authorizedRequest(url)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode([CodexModel].self, from: data)
    }

    // MARK: - Config

    func fetchConfig() async throws -> CodexConfig {
        let url = URL(string: "\(baseURL)/config")!
        let req = authorizedRequest(url)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(CodexConfig.self, from: data)
    }

    func updateConfig(model: String? = nil, reasoningEffort: String? = nil) async throws -> CodexConfig {
        let url = URL(string: "\(baseURL)/config")!
        var req = authorizedRequest(url, method: "PUT")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [:]
        if let model = model { body["model"] = model }
        if let effort = reasoningEffort { body["model_reasoning_effort"] = effort }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(CodexConfig.self, from: data)
    }

    // MARK: - Stats

    func fetchStats() async throws -> ThreadStats {
        let url = URL(string: "\(baseURL)/stats")!
        let req = authorizedRequest(url)
        let (data, response) = try await session.data(for: req)
        try Self.validate(response)
        return try decoder.decode(ThreadStats.self, from: data)
    }

    // MARK: - Validation

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
    }
}

// MARK: - Response types

struct ReplyResponse: Decodable {
    let thread_id: String?
    let status: String
    let message: String?
    let method: String?
    let pid: Int?

    var threadId: String { thread_id ?? "" }

    /// True when the server couldn't deliver the message.
    var isError: Bool {
        status == "busy" || status == "gui_error"
    }

    /// True when message was sent via GUI automation.
    var isSentToGui: Bool {
        status == "sent_to_gui"
    }

    /// User-facing explanation.
    var displayMessage: String {
        message ?? "Message sent."
    }
}

struct ThreadActionResponse: Decodable {
    let status: String
    let thread_id: String?
    let message: String?

    var threadId: String { thread_id ?? "" }
    var isGuiManaged: Bool { status == "gui_managed" }
    var isNotRunning: Bool { status == "not_running" }

    var displayMessage: String {
        message ?? (status == "stopped" ? "Thread stopped." :
                    status == "interrupted" ? "Thread interrupted." : status)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .httpError(401):
            return "Authentication failed. Please re-pair your device in Settings."
        case .httpError(let code):
            return "HTTP error \(code)."
        }
    }
}
