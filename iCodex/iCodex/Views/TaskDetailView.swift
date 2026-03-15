import SwiftUI

struct ThreadDetailView: View {
    let threadId: String
    @StateObject private var vm: ThreadDetailViewModel
    @FocusState private var isReplyFieldFocused: Bool
    private var themeManager = ThemeManager.shared

    init(threadId: String) {
        self.threadId = threadId
        _vm = StateObject(wrappedValue: ThreadDetailViewModel(threadId: threadId))
    }

    private var theme: ThemeColors { themeManager.current }

    var body: some View {
        VStack(spacing: 0) {
            // Thread info header
            if let detail = vm.detail {
                ThreadInfoBar(
                    detail: detail,
                    isRunning: vm.isRunning,
                    config: vm.currentConfig,
                    theme: theme,
                    onModelTap: { vm.showModelPicker = true },
                    onStop: { vm.stopThread() },
                    onInterrupt: { vm.interruptThread() }
                )
            }

            // Status banner
            if let status = vm.statusMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button {
                        vm.statusMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textSecondary)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Messages
            if vm.isLoading {
                Spacer()
                ProgressView("Loading conversation...")
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            } else if let error = vm.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                    Button("Retry") { vm.load() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(vm.userAndAssistantMessages) { msg in
                                MessageBubble(message: msg, theme: theme)
                                    .id(msg.id)
                            }

                            if vm.isRunning {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Codex is working...")
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .id("typing_indicator")
                                .padding(.top, 4)
                            }

                            // Show git stats when thread completed
                            if !vm.isRunning, let detail = vm.detail, let stats = detail.gitStats {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Completed")
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                    Spacer()
                                    GitStatsLabel(stats: stats)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.green.opacity(0.06))
                                )
                                .padding(.horizontal, 12)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(theme.background)
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

            if !vm.mirroredControls.isEmpty {
                MirroredChoicesPanel(
                    theme: theme,
                    isSending: vm.isSendingGUIAction,
                    controls: vm.mirroredControls,
                    onSelect: { control in
                        isReplyFieldFocused = false
                        vm.pressMirroredControl(control)
                    }
                )
            }

            if vm.isRunning {
                GUIControlPad(
                    theme: theme,
                    isSending: vm.isSendingGUIAction,
                    onAction: { action, label in
                        isReplyFieldFocused = false
                        vm.performGUIAction(action, label: label)
                    }
                )
            }

            // Reply input bar
            ReplyBar(
                text: $vm.replyText,
                isSending: vm.isSending,
                isRunning: vm.isRunning,
                isReplyFieldFocused: $isReplyFieldFocused,
                theme: theme,
                onSend: {
                    isReplyFieldFocused = false
                    vm.sendReply()
                }
            )
        }
        .background(theme.background)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") {
                    isReplyFieldFocused = false
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if vm.isRunning {
            proxy.scrollTo("typing_indicator", anchor: .bottom)
        } else if let lastMsg = vm.userAndAssistantMessages.last {
            proxy.scrollTo(lastMsg.id, anchor: .bottom)
        }
    }
}

// MARK: - GUI Control Pad

private struct GUIControl: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let action: String
}

struct MirroredChoicesPanel: View {
    let theme: ThemeColors
    let isSending: Bool
    let controls: [GUIControlOption]
    let onSelect: (GUIControlOption) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Visible Choices")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("Mirrored from Mac")
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(controls) { control in
                    Button {
                        onSelect(control)
                    } label: {
                        HStack(spacing: 8) {
                            if control.selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.accent)
                            }
                            Text(control.title)
                                .font(.caption)
                                .fontWeight(control.focused ? .semibold : .medium)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(theme.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || !control.enabled)
                    .opacity((isSending || !control.enabled) ? 0.55 : 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.headerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)
        }
    }
}

struct GUIControlPad: View {
    let theme: ThemeColors
    let isSending: Bool
    let onAction: (String, String) -> Void

    private let controls: [GUIControl] = [
        GUIControl(id: "prev", title: "Prev", systemImage: "arrow.left.to.line", action: "shift_tab"),
        GUIControl(id: "next", title: "Next", systemImage: "arrow.right.to.line", action: "tab"),
        GUIControl(id: "dismiss", title: "Dismiss", systemImage: "xmark", action: "escape"),
        GUIControl(id: "left", title: "Left", systemImage: "arrow.left", action: "left"),
        GUIControl(id: "up", title: "Up", systemImage: "arrow.up", action: "up"),
        GUIControl(id: "right", title: "Right", systemImage: "arrow.right", action: "right"),
        GUIControl(id: "down", title: "Down", systemImage: "arrow.down", action: "down"),
        GUIControl(id: "space", title: "Space", systemImage: "rectangle.compress.vertical", action: "space"),
        GUIControl(id: "confirm", title: "Confirm", systemImage: "return", action: "enter"),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Remote Controls")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if isSending {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text("Best for Codex desktop prompts")
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(controls) { control in
                    Button {
                        onAction(control.action, control.title)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: control.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                            Text(control.title)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(theme.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.inputBackground)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .opacity(isSending ? 0.6 : 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.headerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Git Stats Label

struct GitStatsLabel: View {
    let stats: GitStats

    var body: some View {
        HStack(spacing: 6) {
            if stats.filesChanged > 0 {
                Text("\(stats.filesChanged) files")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("+\(stats.insertions)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)
            Text("-\(stats.deletions)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Thread Info Bar

struct ThreadInfoBar: View {
    let detail: ThreadDetail
    let isRunning: Bool
    let config: CodexConfig?
    let theme: ThemeColors
    let onModelTap: () -> Void
    let onStop: () -> Void
    let onInterrupt: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if isRunning {
                    PulsingDot()
                    Text("Running")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)

                    Button(action: onInterrupt) {
                        HStack(spacing: 3) {
                            Image(systemName: "pause.circle.fill")
                            Text("Interrupt")
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.1)))
                    }

                    Button(action: onStop) {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.circle.fill")
                            Text("Stop")
                        }
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.1)))
                    }
                }

                Spacer()

                Button(action: onModelTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                        Text(config?.model ?? detail.modelProvider)
                            .fontWeight(.medium)
                        if let effort = config?.modelReasoningEffort, !effort.isEmpty {
                            Text("(\(effort))")
                                .foregroundStyle(theme.textSecondary)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.caption)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.accent.opacity(0.12)))
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
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.headerBackground)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ConversationMessage
    let theme: ThemeColors

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Codex")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(message.isUser ? theme.accent : .green)

                Group {
                    if message.isUser {
                        Text(message.content)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        MarkdownText(text: message.content, theme: theme)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(message.isUser
                              ? theme.bubbleUser
                              : theme.bubbleAssistant)
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
    let isReplyFieldFocused: FocusState<Bool>.Binding
    let theme: ThemeColors
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 0.5)
            HStack(spacing: 8) {
                TextField(
                    isRunning ? "Send instruction to Codex..." : "Reply to thread...",
                    text: $text,
                    axis: .vertical
                )
                .focused(isReplyFieldFocused)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit(onSend)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(theme.inputBackground)
                )

                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(theme.accent)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(theme.headerBackground)
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
