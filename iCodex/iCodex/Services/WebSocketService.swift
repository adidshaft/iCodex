import Foundation
import Combine

final class WebSocketService: ObservableObject {
    @Published var newMessages: [ConversationMessage] = []
    @Published var isConnected: Bool = false
    @Published var threadIsRunning: Bool = false

    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var currentPath: String?
    private var shouldReconnect = true

    // Callbacks for live feed
    var onThreadsUpdate: (([CodexThread]) -> Void)?
    var onNewMessage: ((String, ConversationMessage) -> Void)?

    init() {
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connect to global live feed

    func connectLive() {
        shouldReconnect = true
        reconnectAttempts = 0
        currentPath = "/ws/live"
        doConnect(path: "/ws/live")
    }

    // MARK: - Connect to a specific thread

    func connectThread(threadId: String) {
        shouldReconnect = true
        reconnectAttempts = 0
        newMessages = []
        currentPath = "/ws/thread/\(threadId)"
        doConnect(path: "/ws/thread/\(threadId)")
    }

    func disconnect() {
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    // MARK: - Internal

    private func doConnect(path: String) {
        let wsBase = ServerConfig.shared.baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        let token = ServerConfig.shared.apiKey
        let separator = path.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(wsBase)\(path)\(separator)token=\(token)") else { return }

        task = session.webSocketTask(with: url)
        task?.resume()
        DispatchQueue.main.async {
            self.isConnected = true
        }
        reconnectAttempts = 0
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                default:
                    break
                }
                self.listen()

            case .failure:
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                self.attemptReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "threads_update":
            // Decode full thread list
            if let threadsData = try? JSONSerialization.data(withJSONObject: json["threads"] ?? []),
               let threads = try? JSONDecoder().decode([CodexThread].self, from: threadsData) {
                DispatchQueue.main.async {
                    self.onThreadsUpdate?(threads)
                }
            }

        case "new_message":
            // Decode a single conversation message
            if let msgData = try? JSONSerialization.data(withJSONObject: json["message"] ?? [:]),
               let msg = try? JSONDecoder().decode(ConversationMessage.self, from: msgData) {
                let threadId = json["thread_id"] as? String ?? ""
                DispatchQueue.main.async {
                    self.newMessages.append(msg)
                    self.onNewMessage?(threadId, msg)
                }
            }

        case "thread_status":
            if let running = json["is_running"] as? Bool {
                DispatchQueue.main.async {
                    self.threadIsRunning = running
                }
            }

        default:
            break
        }
    }

    private func attemptReconnect() {
        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else { return }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.shouldReconnect, let path = self.currentPath else { return }
            self.doConnect(path: path)
        }
    }
}
