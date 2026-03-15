import Foundation
import Combine

@MainActor
final class ThreadDetailViewModel: ObservableObject {
    @Published var detail: ThreadDetail?
    @Published var messages: [ConversationMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var replyText: String = ""
    @Published var isSending = false
    @Published var isRunning = false
    @Published var statusMessage: String?

    // Model switching
    @Published var availableModels: [CodexModel] = []
    @Published var currentConfig: CodexConfig?
    @Published var showModelPicker = false

    let threadId: String
    let wsService = WebSocketService()
    private var cancellables = Set<AnyCancellable>()

    init(threadId: String) {
        self.threadId = threadId
    }

    var userAndAssistantMessages: [ConversationMessage] {
        messages.filter { $0.isUser || $0.isAssistant }
    }

    func load() {
        isLoading = true
        errorMessage = nil
        statusMessage = nil

        // Connect WebSocket for real-time updates
        wsService.connectThread(threadId: threadId)
        wsService.$newMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMsgs in
                guard let self = self else { return }
                for msg in newMsgs where !self.messages.contains(where: { $0.content == msg.content && $0.role == msg.role && $0.timestamp == msg.timestamp }) {
                    self.messages.append(msg)
                }
            }
            .store(in: &cancellables)

        wsService.$threadIsRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.isRunning = running
                if !running {
                    self?.statusMessage = nil
                }
            }
            .store(in: &cancellables)

        Task {
            do {
                async let detailReq = APIService.shared.fetchThreadDetail(threadId)
                async let msgsReq = APIService.shared.fetchThreadMessages(threadId)
                async let modelsReq = APIService.shared.fetchModels()
                async let configReq = APIService.shared.fetchConfig()
                let (d, m, models, config) = try await (detailReq, msgsReq, modelsReq, configReq)
                self.detail = d
                self.messages = m
                self.isRunning = d.isRunning
                self.availableModels = models
                self.currentConfig = config
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        statusMessage = nil

        Task {
            do {
                let response = try await APIService.shared.replyToThread(threadId, message: text)
                if response.isError {
                    // Thread is managed by GUI or busy — show message to user
                    self.statusMessage = response.displayMessage
                } else {
                    self.replyText = ""
                    self.isRunning = true
                }
            } catch {
                self.errorMessage = "Failed to send: \(error.localizedDescription)"
            }
            self.isSending = false
        }
    }

    func stopThread() {
        statusMessage = nil
        Task {
            do {
                let response = try await APIService.shared.stopThread(threadId)
                if response.isGuiManaged || response.isNotRunning {
                    self.statusMessage = response.displayMessage
                } else {
                    self.isRunning = false
                    self.statusMessage = "Thread stopped."
                }
            } catch {
                self.statusMessage = "Failed to stop: \(error.localizedDescription)"
            }
        }
    }

    func interruptThread() {
        statusMessage = nil
        Task {
            do {
                let response = try await APIService.shared.interruptThread(threadId)
                if response.isGuiManaged || response.isNotRunning {
                    self.statusMessage = response.displayMessage
                } else {
                    self.statusMessage = "Interrupt signal sent."
                }
            } catch {
                self.statusMessage = "Failed to interrupt: \(error.localizedDescription)"
            }
        }
    }

    func switchModel(to slug: String) {
        Task {
            do {
                self.currentConfig = try await APIService.shared.updateConfig(model: slug)
            } catch {
                self.errorMessage = "Failed to switch model: \(error.localizedDescription)"
            }
        }
    }

    func switchReasoningLevel(to level: String) {
        Task {
            do {
                self.currentConfig = try await APIService.shared.updateConfig(reasoningEffort: level)
            } catch {
                self.errorMessage = "Failed to change level: \(error.localizedDescription)"
            }
        }
    }

    func cleanup() {
        wsService.disconnect()
        cancellables.removeAll()
    }
}
