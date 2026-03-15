import SwiftUI

struct ThreadDetailView: View {
    let threadId: String
    @StateObject private var vm: ThreadDetailViewModel

    init(threadId: String) {
        self.threadId = threadId
        _vm = StateObject(wrappedValue: ThreadDetailViewModel(threadId: threadId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thread info header
            if let detail = vm.detail {
                ThreadInfoBar(detail: detail, isRunning: vm.isRunning, config: vm.currentConfig, onModelTap: {
                    vm.showModelPicker = true
                })
            }

            // Status banner (gui_managed, busy, stopped, etc.)
            if let status = vm.statusMessage {
                StatusBanner(message: status, onDismiss: { vm.statusMessage = nil })
            }

            // Messages
            if vm.isLoading {
                Spacer()
                ProgressView("Loading conversation...")
                Spacer()
            } else if let error = vm.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { vm.load() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(vm.userAndAssistantMessages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if vm.isRunning {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Codex is working...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .id("typing_indicator")
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: vm.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
            }

            // Reply input bar
            ReplyBar(
                text: $vm.replyText,
                isSending: vm.isSending,
                isRunning: vm.isRunning,
                onSend: { vm.sendReply() },
                onStop: { vm.stopThread() },
                onInterrupt: { vm.interruptThread() }
            )
        }
        .navigationTitle(vm.detail?.title.prefix(25).description ?? "Thread")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $vm.showModelPicker) {
            ModelPickerSheet(
                models: vm.availableModels,
                currentModel: vm.currentConfig?.model ?? "",
                currentLevel: vm.currentConfig?.modelReasoningEffort ?? "",
                onSelectModel: { vm.switchModel(to: $0) },
                onSelectLevel: { vm.switchReasoningLevel(to: $0) }
            )
        }
        .onAppear { vm.load() }
        .onDisappear { vm.cleanup() }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if vm.isRunning {
            proxy.scrollTo("typing_indicator", anchor: .bottom)
        } else if let lastMsg = vm.userAndAssistantMessages.last {
            proxy.scrollTo(lastMsg.id, anchor: .bottom)
        }
    }
}

// MARK: - Status Banner

struct StatusBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Thread Info Bar

struct ThreadInfoBar: View {
    let detail: ThreadDetail
    let isRunning: Bool
    let config: CodexConfig?
    let onModelTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if isRunning {
                    PulsingDot()
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                }

                Spacer()

                Button(action: onModelTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(config?.model ?? detail.modelProvider)
                            .fontWeight(.medium)
                        if let effort = config?.modelReasoningEffort, !effort.isEmpty {
                            Text("(\(effort))")
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.1)))
                }
            }

            HStack(spacing: 12) {
                Label(detail.projectName, systemImage: "folder")
                if let branch = detail.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                }
                Spacer()
                Text("\(detail.formattedTokens) tokens")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Codex")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(message.isUser ? .blue : .green)

                Text(message.content)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(message.isUser
                                  ? Color.blue.opacity(0.12)
                                  : Color(uiColor: .tertiarySystemBackground))
                    )
                    .textSelection(.enabled)
            }

            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Reply Bar

struct ReplyBar: View {
    @Binding var text: String
    let isSending: Bool
    let isRunning: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onInterrupt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                // Stop / Interrupt buttons when running
                if isRunning {
                    Menu {
                        Button(role: .destructive, action: onStop) {
                            Label("Stop Thread", systemImage: "stop.fill")
                        }
                        Button(action: onInterrupt) {
                            Label("Interrupt", systemImage: "pause.fill")
                        }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                }

                TextField(
                    isRunning ? "Send instruction to Codex..." : "Reply to thread...",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                )

                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    let models: [CodexModel]
    let currentModel: String
    let currentLevel: String
    let onSelectModel: (String) -> Void
    let onSelectLevel: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    let reasoningLevels = ["low", "medium", "high", "xhigh"]

    var body: some View {
        NavigationStack {
            List {
                Section("Reasoning Level") {
                    ForEach(reasoningLevels, id: \.self) { level in
                        Button {
                            onSelectLevel(level)
                        } label: {
                            HStack {
                                Text(level.capitalized)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if level == currentLevel {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Model") {
                    ForEach(models) { model in
                        Button {
                            onSelectModel(model.slug)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(model.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if model.slug == currentModel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                if !model.description.isEmpty {
                                    Text(model.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Model & Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
