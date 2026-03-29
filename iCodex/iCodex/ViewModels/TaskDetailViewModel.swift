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
    @Published var remoteSession: GUIRemoteSession?
    @Published var remoteAvailabilityMessage: String?
    @Published var isCodexGUIAvailable = false
    @Published var remoteReady = false
    @Published var supportedRemoteActions: [String] = []

    // Model switching
    @Published var availableModels: [CodexModel] = []
    @Published var currentConfig: CodexConfig?
    @Published var showModelPicker = false

    let threadId: String
    let wsService = WebSocketService()
    private var cancellables = Set<AnyCancellable>()
    private var controlsPollTask: Task<Void, Never>?
    private var isSceneActive = true

    init(threadId: String) {
        self.threadId = threadId
    }

    var userAndAssistantMessages: [ConversationMessage] {
        messages.filter { $0.isUser || $0.isAssistant }
    }

    var supportsRemoteCompanion: Bool {
        detail?.source == "vscode"
    }

    var shouldShowRemoteCompanion: Bool {
        supportsRemoteCompanion
    }

    var remoteStatusTitle: String {
        if !supportsRemoteCompanion {
            return "Remote unavailable"
        }
        if remoteReady {
            return isRunning ? "Codex live" : "Remote ready"
        }
        if remoteSession?.locked == true {
            return "Mac locked"
        }
        if !isCodexGUIAvailable {
            return "Codex closed"
        }
        return "Checking Mac"
    }

    var remoteStatusSubtitle: String {
        if let message = remoteAvailabilityMessage, !message.isEmpty {
            return message
        }
        if remoteReady {
            return isRunning
                ? "Use controls, mirrored choices, or send a follow-up while Codex runs."
                : "Navigate this Codex thread remotely and keep the handoff ready."
        }
        if remoteSession?.screensaverRunning == true {
            return "The screen saver is active. Wake or unlock the Mac session to continue control."
        }
        return "Connect to the Codex desktop thread to enable remote actions."
    }

    var remoteStatusSymbol: String {
        if remoteReady { return "dot.radiowaves.left.and.right" }
        if remoteSession?.locked == true { return "lock.fill" }
        if !isCodexGUIAvailable { return "macbook.and.iphone" }
        return "clock.arrow.circlepath"
    }

    func supportsRemoteAction(_ action: String) -> Bool {
        supportedRemoteActions.isEmpty || supportedRemoteActions.contains(action)
    }

    func load() {
        isLoading = true
        errorMessage = nil

        wsService.disconnect()
        cancellables.removeAll()
        controlsPollTask?.cancel()
        controlsPollTask = nil

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
                self.startRemotePolling()
                await self.refreshRemoteState(force: true)
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
            await self.refreshRemoteState(force: true)
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
            await self.refreshRemoteState(force: true)
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
            await self.refreshRemoteState(force: true)
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
            await self.refreshRemoteState(force: true)
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
            await self.refreshRemoteState(force: true)
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
            await self.refreshRemoteState(force: true)
        }
    }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if active {
            Task {
                await refreshRemoteState(force: true)
            }
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

    private func startRemotePolling() {
        controlsPollTask?.cancel()
        controlsPollTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                if self.isSceneActive {
                    await self.refreshRemoteState()
                }

                let interval: UInt64
                if !self.supportsRemoteCompanion {
                    interval = 5_000_000_000
                } else if !self.isSceneActive {
                    interval = 4_000_000_000
                } else if self.isRunning {
                    interval = 1_250_000_000
                } else {
                    interval = 2_750_000_000
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func clearRemoteState(message: String? = nil) {
        if !mirroredControls.isEmpty {
            mirroredControls = []
        }
        remoteSession = nil
        remoteAvailabilityMessage = message
        isCodexGUIAvailable = false
        remoteReady = false
        supportedRemoteActions = []
    }

    private func refreshRemoteState(force: Bool = false) async {
        guard supportsRemoteCompanion else {
            clearRemoteState()
            return
        }

        // Avoid refocusing the Mac thread while we're actively sending text or
        // pressing a GUI action from iPhone unless we explicitly need a refresh.
        guard force || (!isSending && !isSendingGUIAction) else {
            return
        }

        do {
            let response = try await APIService.shared.fetchGUIControls(threadId)
            remoteSession = response.sessionState
            remoteAvailabilityMessage = response.message
            isCodexGUIAvailable = response.codexRunning ?? false
            remoteReady = response.remoteReady ?? false
            supportedRemoteActions = response.supportedActions ?? []

            let controls = (response.controls ?? []).filter { !$0.title.isEmpty }
            if controls != mirroredControls {
                mirroredControls = controls
            }
        } catch {
            clearRemoteState(message: "Could not reach the Mac helper.")
        }
    }
}
