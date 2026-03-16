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
    @Published var isSendingGUIAction = false
    @Published var isRunning = false
    @Published var statusMessage: String?
    @Published var mirroredControls: [GUIControlOption] = []

    // Model switching
    @Published var availableModels: [CodexModel] = []
    @Published var currentConfig: CodexConfig?
    @Published var showModelPicker = false

    let threadId: String
    let wsService = WebSocketService()
    private var cancellables = Set<AnyCancellable>()
    private var controlsPollTask: Task<Void, Never>?

    init(threadId: String) {
        self.threadId = threadId
    }

    var userAndAssistantMessages: [ConversationMessage] {
        messages.filter { $0.isUser || $0.isAssistant }
    }

    func load() {
        isLoading = true
        errorMessage = nil

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
            .sink { [weak self] (running: Bool) in
                guard let self = self else { return }
                let wasRunning = self.isRunning
                self.isRunning = running
                // When thread finishes, re-fetch detail to get git stats
                if wasRunning && !running {
                    self.refreshDetail()
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
                self.startMirroredControlsPolling()
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
                let reply = try await APIService.shared.replyToThread(threadId, message: text)
                if reply.isError {
                    self.showTemporaryStatus(reply.displayMessage)
                } else {
                    self.replyText = ""
                    self.messages.append(ConversationMessage(
                        role: "user", content: text, timestamp: nil, type: "message"
                    ))
                }

                if reply.isSentToGui {
                    self.showTemporaryStatus("Sent to Codex GUI")
                    self.isRunning = true
                } else if reply.status == "resumed" {
                    self.isRunning = true
                }
            } catch {
                self.errorMessage = "Failed to send: \(error.localizedDescription)"
            }
            self.isSending = false
        }
    }

    func stopThread() {
        Task {
            do {
                let result = try await APIService.shared.stopThread(threadId)
                switch result.status {
                case "stopped":
                    self.isRunning = false
                    self.showTemporaryStatus("Thread stopped.")
                case "not_running":
                    self.isRunning = false
                    self.showTemporaryStatus("Thread is not running.")
                default:
                    if let msg = result.message {
                        self.showTemporaryStatus(msg)
                    }
                }
            } catch {
                self.errorMessage = "Failed to stop: \(error.localizedDescription)"
            }
        }
    }

    func interruptThread() {
        Task {
            do {
                let result = try await APIService.shared.interruptThread(threadId)
                switch result.status {
                case "interrupted":
                    self.showTemporaryStatus("Interrupt sent.")
                case "not_running":
                    self.showTemporaryStatus("Thread is not running.")
                default:
                    if let msg = result.message {
                        self.showTemporaryStatus(msg)
                    }
                }
            } catch {
                self.errorMessage = "Failed to interrupt: \(error.localizedDescription)"
            }
        }
    }

    func performGUIAction(_ action: String, label: String) {
        isSendingGUIAction = true
        Task {
            do {
                let result = try await APIService.shared.performGUIAction(threadId, action: action)
                switch result.status {
                case "sent":
                    self.showTemporaryStatus("\(label) sent.")
                case "not_running":
                    self.isRunning = false
                    self.showTemporaryStatus("Thread is not running.")
                default:
                    if let msg = result.message {
                        self.showTemporaryStatus(msg)
                    }
                }
            } catch {
                self.errorMessage = "Failed to send control: \(error.localizedDescription)"
            }
            self.isSendingGUIAction = false
            await self.refreshMirroredControls()
        }
    }

    func pressMirroredControl(_ control: GUIControlOption) {
        isSendingGUIAction = true
        Task {
            do {
                let result = try await APIService.shared.pressGUIControl(threadId, controlId: control.id)
                switch result.status {
                case "pressed":
                    self.showTemporaryStatus("\(control.title) selected.")
                default:
                    if let msg = result.message {
                        self.showTemporaryStatus(msg)
                    }
                }
            } catch {
                self.errorMessage = "Failed to select option: \(error.localizedDescription)"
            }
            self.isSendingGUIAction = false
            await self.refreshMirroredControls()
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

    func refreshDetail() {
        Task {
            if let d = try? await APIService.shared.fetchThreadDetail(threadId) {
                self.detail = d
            }
            if let msgs = try? await APIService.shared.fetchThreadMessages(threadId) {
                self.messages = msgs
            }
            await self.refreshMirroredControls()
        }
    }

    func cleanup() {
        wsService.disconnect()
        cancellables.removeAll()
        controlsPollTask?.cancel()
        controlsPollTask = nil
    }

    private func showTemporaryStatus(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self = self, self.statusMessage == message else { return }
            self.statusMessage = nil
        }
    }

    private func startMirroredControlsPolling() {
        controlsPollTask?.cancel()
        controlsPollTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                await self.refreshMirroredControls()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func refreshMirroredControls() async {
        guard detail?.source == "vscode" else {
            if !mirroredControls.isEmpty {
                mirroredControls = []
            }
            return
        }

        // Avoid refocusing the Mac thread while we're actively sending text or
        // pressing a GUI action from iPhone.
        guard !isSending, !isSendingGUIAction else {
            return
        }

        guard isRunning else {
            if !mirroredControls.isEmpty {
                mirroredControls = []
            }
            return
        }

        do {
            let response = try await APIService.shared.fetchGUIControls(threadId)
            let controls = (response.controls ?? []).filter { !$0.title.isEmpty }
            if controls != mirroredControls {
                mirroredControls = controls
            }
        } catch {
            if !mirroredControls.isEmpty {
                mirroredControls = []
            }
        }
    }
}
