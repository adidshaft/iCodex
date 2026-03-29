import SwiftUI

struct ModelsView: View {
    @StateObject private var vm = ModelsViewModel()
    private var themeManager = ThemeManager.shared

    private var activeModelSlug: String? {
        vm.config?.model
    }

    private var activeReasoning: String {
        vm.config?.modelReasoningEffort.capitalized ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                Group {
                    if vm.isLoading && vm.models.isEmpty {
                        loadingState
                    } else if let error = vm.errorMessage, vm.models.isEmpty {
                        errorState(message: error)
                    } else {
                        mainContent
                    }
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if vm.models.isEmpty {
                    vm.load()
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.15)
                .tint(themeManager.current.accent)

            Text("Loading connector configuration...")
                .font(.subheadline)
                .foregroundStyle(themeManager.current.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 82, height: 82)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Couldn’t load models")
                    .font(.headline)
                    .foregroundStyle(themeManager.current.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.current.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                vm.load()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeManager.current.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if let error = vm.errorMessage {
                    inlineBanner(
                        title: "Connection warning",
                        message: error,
                        icon: "wifi.exclamationmark",
                        color: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available on your Mac")
                                .font(.headline)
                                .foregroundStyle(themeManager.current.textPrimary)
                            Text("This screen mirrors the model list from iCodex-Connect.")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.current.textSecondary)
                        }

                        Spacer()

                        Text("\(vm.models.count)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(themeManager.current.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(themeManager.current.surface)
                            )
                    }

                    if vm.models.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.models) { model in
                            modelCard(model)
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .refreshable {
            vm.load()
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Connector Setup")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .textCase(.uppercase)
                        .foregroundStyle(themeManager.current.textSecondary.opacity(0.85))

                    Text(vm.config?.model ?? "No active model")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(themeManager.current.textPrimary)
                        .lineLimit(2)

                    Text("Your iPhone reflects whatever model and reasoning level are active on the Mac connector.")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.current.textSecondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "cpu.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(themeManager.current.accent)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(themeManager.current.inputBackground.opacity(0.95))
                    )
            }

            HStack(spacing: 10) {
                summaryPill(title: "Reasoning", value: activeReasoning)
                summaryPill(title: "MCP", value: "\(vm.config?.mcpServers.count ?? 0) servers")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(themeManager.current.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(themeManager.current.divider.opacity(0.75), lineWidth: 1)
        )
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(themeManager.current.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.current.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(themeManager.current.inputBackground)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(themeManager.current.textSecondary.opacity(0.7))

            Text("No models reported yet")
                .font(.headline)
                .foregroundStyle(themeManager.current.textPrimary)

            Text("Refresh the screen after iCodex-Connect finishes loading your Mac configuration.")
                .font(.subheadline)
                .foregroundStyle(themeManager.current.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(themeManager.current.surface)
        )
    }

    private func modelCard(_ model: CodexModel) -> some View {
        let isActive = model.slug == activeModelSlug

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? themeManager.current.accent.opacity(0.16) : themeManager.current.inputBackground)
                        .frame(width: 50, height: 50)

                    Image(systemName: isActive ? "checkmark.seal.fill" : "cpu")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isActive ? themeManager.current.accent : themeManager.current.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(model.displayName)
                            .font(.headline)
                            .foregroundStyle(themeManager.current.textPrimary)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(themeManager.current.background)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(themeManager.current.accent)
                                )
                        }
                    }

                    Text(model.slug)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(themeManager.current.textSecondary)
                }

                Spacer()
            }

            if !model.description.isEmpty {
                Text(model.description)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.current.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.supportedReasoningLevels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reasoning levels")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(themeManager.current.textSecondary)

                    FlexibleTagWrap(items: model.supportedReasoningLevels.map(\.effort)) { effort in
                        Text(effort.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isActive ? themeManager.current.accent : themeManager.current.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(
                                        isActive
                                            ? themeManager.current.accent.opacity(0.12)
                                            : themeManager.current.inputBackground
                                    )
                            )
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(themeManager.current.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isActive ? themeManager.current.accent.opacity(0.55) : themeManager.current.divider.opacity(0.55),
                    lineWidth: 1
                )
        )
    }

    private func inlineBanner(title: String, message: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .padding(10)
                .background(
                    Circle()
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.current.textPrimary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(themeManager.current.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(themeManager.current.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct FlexibleTagWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    content(item)
                }
            }
        }
    }
}
