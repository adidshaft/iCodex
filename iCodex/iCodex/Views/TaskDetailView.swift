import SwiftUI

struct ThreadDetailView: View {
    let threadId: String
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm: ThreadDetailViewModel
    @FocusState private var isReplyFieldFocused: Bool
    @State private var remoteDeckExpanded = true
    @State private var selectedRemoteDeckSection: RemoteDeckSection = .controls
    private var themeManager = ThemeManager.shared

    init(threadId: String) {
        self.threadId = threadId
        _vm = StateObject(wrappedValue: ThreadDetailViewModel(threadId: threadId))
    }

    private var theme: ThemeColors { themeManager.current }

    var body: some View {
        ZStack {
            ThreadBackdrop(theme: theme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
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

                if let status = vm.statusMessage {
                    StatusBanner(theme: theme, text: status) {
                        vm.statusMessage = nil
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

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
                            VStack(spacing: 12) {
                                if vm.shouldShowRemoteCompanion {
                                    RemoteCompanionDeck(
                                        theme: theme,
                                        isExpanded: $remoteDeckExpanded,
                                        selectedSection: $selectedRemoteDeckSection,
                                        isSending: vm.isSendingGUIAction,
                                        isRunning: vm.isRunning,
                                        statusTitle: vm.remoteStatusTitle,
                                        statusSubtitle: vm.remoteStatusSubtitle,
                                        statusSymbol: vm.remoteStatusSymbol,
                                        remoteReady: vm.remoteReady,
                                        mirroredControls: vm.mirroredControls,
                                        supportsAction: { vm.supportsRemoteAction($0) },
                                        onHideKeyboard: { isReplyFieldFocused = false },
                                        onSelectChoice: { control in
                                            isReplyFieldFocused = false
                                            vm.pressMirroredControl(control)
                                        },
                                        onPerformAction: { command in
                                            isReplyFieldFocused = false
                                            switch command.kind {
                                            case .interrupt:
                                                vm.interruptThread()
                                            case .stop:
                                                vm.stopThread()
                                            case .guiAction(let action):
                                                vm.performGUIAction(action, label: command.title)
                                            }
                                        }
                                    )
                                }

                                LazyVStack(spacing: 10) {
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
                                        .padding(.top, 6)
                                    }

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
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(.thinMaterial)
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(Color.green.opacity(0.18), lineWidth: 1)
                                                }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 18)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .background(Color.clear)
                        .onAppear {
                            scrollToBottom(proxy: proxy)
                        }
                        .onChange(of: vm.messages.count, initial: false) { _, _ in
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollToBottom(proxy: proxy)
                            }
                        }
                    }
                }

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
        .onChange(of: scenePhase, initial: true) { _, newValue in
            vm.setSceneActive(newValue == .active)
        }
        .onChange(of: isReplyFieldFocused, initial: false) { _, focused in
            if focused && remoteDeckExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    remoteDeckExpanded = false
                }
            }
        }
        .onChange(of: vm.mirroredControls.count, initial: false) { _, count in
            if count > 0 {
                selectedRemoteDeckSection = .choices
                if !isReplyFieldFocused {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        remoteDeckExpanded = true
                    }
                }
            } else if selectedRemoteDeckSection == .choices {
                selectedRemoteDeckSection = .controls
            }
        }
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

// MARK: - Remote Companion

enum RemoteDeckSection: String, CaseIterable, Identifiable {
    case controls = "Controls"
    case choices = "Choices"

    var id: String { rawValue }
}

enum RemoteCommandKind {
    case guiAction(String)
    case interrupt
    case stop
}

struct RemoteCommand: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let kind: RemoteCommandKind
    let tint: Color
}

private struct ThreadBackdrop: View {
    let theme: ThemeColors

    var body: some View {
        LinearGradient(
            colors: [
                theme.background,
                theme.surface.opacity(0.96),
                theme.background,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(theme.accent.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 80, y: -40)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 180, height: 180)
                .blur(radius: 70)
                .offset(x: -40, y: 60)
        }
    }
}

private struct StatusBanner: View {
    let theme: ThemeColors
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(theme.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.textSecondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RemoteSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), theme: theme))
    }
}

private struct RemoteSurface<S: InsettableShape>: View {
    let shape: S
    let theme: ThemeColors

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape
                    .fill(theme.surface.opacity(0.30))
            }
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
    }
}

struct MirroredChoicesPanel: View {
    let theme: ThemeColors
    let isSending: Bool
    let controls: [GUIControlOption]
    let onSelect: (GUIControlOption) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Visible Choices")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("\(controls.count) mirrored")
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
                            RemoteSurface(
                                shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                theme: theme
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || !control.enabled)
                    .opacity((isSending || !control.enabled) ? 0.55 : 1)
                }
            }
        }
    }
}

struct RemoteCompanionDeck: View {
    let theme: ThemeColors
    @Binding var isExpanded: Bool
    @Binding var selectedSection: RemoteDeckSection
    let isSending: Bool
    let isRunning: Bool
    let statusTitle: String
    let statusSubtitle: String
    let statusSymbol: String
    let remoteReady: Bool
    let mirroredControls: [GUIControlOption]
    let supportsAction: (String) -> Bool
    let onHideKeyboard: () -> Void
    let onSelectChoice: (GUIControlOption) -> Void
    let onPerformAction: (RemoteCommand) -> Void

    private let primaryCommands: [RemoteCommand] = [
        RemoteCommand(id: "interrupt", title: "Interrupt", systemImage: "pause.circle.fill", kind: .interrupt, tint: .orange),
        RemoteCommand(id: "stop", title: "Stop", systemImage: "stop.circle.fill", kind: .stop, tint: .red),
        RemoteCommand(id: "confirm", title: "Confirm", systemImage: "return", kind: .guiAction("enter"), tint: .green),
        RemoteCommand(id: "dismiss", title: "Dismiss", systemImage: "xmark", kind: .guiAction("escape"), tint: .secondary),
    ]

    private let navigationCommands: [RemoteCommand] = [
        RemoteCommand(id: "prev", title: "Prev", systemImage: "arrow.left.to.line", kind: .guiAction("shift_tab"), tint: .blue),
        RemoteCommand(id: "next", title: "Next", systemImage: "arrow.right.to.line", kind: .guiAction("tab"), tint: .blue),
        RemoteCommand(id: "page_up", title: "Page Up", systemImage: "arrow.up.doc", kind: .guiAction("page_up"), tint: .purple),
        RemoteCommand(id: "page_down", title: "Page Down", systemImage: "arrow.down.doc", kind: .guiAction("page_down"), tint: .purple),
        RemoteCommand(id: "top", title: "Top", systemImage: "arrow.up.to.line", kind: .guiAction("jump_top"), tint: .mint),
        RemoteCommand(id: "bottom", title: "Bottom", systemImage: "arrow.down.to.line", kind: .guiAction("jump_bottom"), tint: .mint),
        RemoteCommand(id: "space", title: "Space", systemImage: "rectangle.compress.vertical", kind: .guiAction("space"), tint: .teal),
    ]

    private let arrowCommands: [RemoteCommand] = [
        RemoteCommand(id: "left", title: "Left", systemImage: "arrow.left", kind: .guiAction("left"), tint: .indigo),
        RemoteCommand(id: "up", title: "Up", systemImage: "arrow.up", kind: .guiAction("up"), tint: .indigo),
        RemoteCommand(id: "right", title: "Right", systemImage: "arrow.right", kind: .guiAction("right"), tint: .indigo),
        RemoteCommand(id: "down", title: "Down", systemImage: "arrow.down", kind: .guiAction("down"), tint: .indigo),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(remoteReady ? .green : theme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(remoteReady ? Color.green.opacity(0.16) : theme.accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Remote Companion")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary)

                        Text(statusTitle)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(remoteReady ? .green : theme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(remoteReady ? Color.green.opacity(0.14) : Color.white.opacity(0.08))
                            )
                    }

                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button(action: onHideKeyboard) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RemoteSurface(shape: Circle(), theme: theme)
                    )

                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RemoteSurface(shape: Circle(), theme: theme)
                    )
                }
                .foregroundStyle(theme.textPrimary)
            }

            if isExpanded {
                if !mirroredControls.isEmpty {
                    Picker("Remote Section", selection: $selectedSection) {
                        Text("Controls").tag(RemoteDeckSection.controls)
                        Text("Choices").tag(RemoteDeckSection.choices)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedSection == .choices && !mirroredControls.isEmpty {
                    MirroredChoicesPanel(
                        theme: theme,
                        isSending: isSending,
                        controls: mirroredControls,
                        onSelect: onSelectChoice
                    )
                } else {
                    RemoteControlsPanel(
                        theme: theme,
                        isSending: isSending,
                        isRunning: isRunning,
                        primaryCommands: primaryCommands,
                        navigationCommands: navigationCommands,
                        arrowCommands: arrowCommands,
                        supportsAction: supportsAction,
                        onPerformAction: onPerformAction
                    )
                }
            }
        }
        .padding(14)
        .background(
            RemoteSurface(
                shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
                theme: theme
            )
        )
    }
}

struct RemoteControlsPanel: View {
    let theme: ThemeColors
    let isSending: Bool
    let isRunning: Bool
    let primaryCommands: [RemoteCommand]
    let navigationCommands: [RemoteCommand]
    let arrowCommands: [RemoteCommand]
    let supportsAction: (String) -> Bool
    let onPerformAction: (RemoteCommand) -> Void

    private let primaryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)
    private let secondaryColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let directionalColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isSending {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sending remote action to Codex…")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Live Actions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)

                LazyVGrid(columns: primaryColumns, spacing: 8) {
                    ForEach(primaryCommands) { command in
                        RemoteCommandButton(
                            theme: theme,
                            command: command,
                            isEnabled: isCommandEnabled(command),
                            isSending: isSending,
                            onTap: { onPerformAction(command) }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Navigate")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)

                LazyVGrid(columns: secondaryColumns, spacing: 8) {
                    ForEach(navigationCommands) { command in
                        RemoteCommandButton(
                            theme: theme,
                            command: command,
                            isEnabled: isCommandEnabled(command),
                            isSending: isSending,
                            onTap: { onPerformAction(command) }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Directional Pad")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)

                LazyVGrid(columns: directionalColumns, spacing: 8) {
                    Color.clear
                        .frame(height: 52)
                    RemoteCommandButton(
                        theme: theme,
                        command: arrowCommands[1],
                        isEnabled: isCommandEnabled(arrowCommands[1]),
                        isSending: isSending,
                        onTap: { onPerformAction(arrowCommands[1]) }
                    )
                    Color.clear
                        .frame(height: 52)

                    RemoteCommandButton(
                        theme: theme,
                        command: arrowCommands[0],
                        isEnabled: isCommandEnabled(arrowCommands[0]),
                        isSending: isSending,
                        onTap: { onPerformAction(arrowCommands[0]) }
                    )
                    RemoteCommandButton(
                        theme: theme,
                        command: arrowCommands[3],
                        isEnabled: isCommandEnabled(arrowCommands[3]),
                        isSending: isSending,
                        onTap: { onPerformAction(arrowCommands[3]) }
                    )
                    RemoteCommandButton(
                        theme: theme,
                        command: arrowCommands[2],
                        isEnabled: isCommandEnabled(arrowCommands[2]),
                        isSending: isSending,
                        onTap: { onPerformAction(arrowCommands[2]) }
                    )
                }
            }
        }
    }

    private func isCommandEnabled(_ command: RemoteCommand) -> Bool {
        switch command.kind {
        case .interrupt, .stop:
            return isRunning
        case .guiAction(let action):
            return supportsAction(action)
        }
    }
}

struct RemoteCommandButton: View {
    let theme: ThemeColors
    let command: RemoteCommand
    let isEnabled: Bool
    let isSending: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                Image(systemName: command.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(command.title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isEnabled ? theme.textPrimary : theme.textSecondary)
            .background(
                RemoteSurface(
                    shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    theme: theme
                )
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(command.tint.opacity(isEnabled ? 0.9 : 0.25))
                    .frame(width: 8, height: 8)
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isSending)
        .opacity((!isEnabled || isSending) ? 0.55 : 1)
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
                    .background(
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay {
                                Capsule()
                                    .fill(theme.accent.opacity(0.10))
                            }
                    )
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
        .padding(.vertical, 10)
        .background(
            RemoteSurface(
                shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
                theme: theme
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
        )
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
                    RemoteSurface(
                        shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                        theme: theme
                    )
                )

                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.accent.gradient)
                )
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? 0.55 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(
            RemoteSurface(
                shape: RoundedRectangle(cornerRadius: 26, style: .continuous),
                theme: theme
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        )
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
