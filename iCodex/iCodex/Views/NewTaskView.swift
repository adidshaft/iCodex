import SwiftUI

struct ModelsView: View {
    @StateObject private var vm = ModelsViewModel()
    private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                Group {
                    if vm.isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(themeManager.current.accent)
                            Text("Loading models...")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.current.textSecondary)
                        }
                    } else if let error = vm.errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(themeManager.current.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Button("Retry") { vm.load() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        List {
                            // Active Config Card
                            if let config = vm.config {
                                Section {
                                    activeConfigCard(config: config)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                            }

                            // Available Models
                            Section {
                                ForEach(vm.models) { model in
                                    modelRow(model: model)
                                        .listRowBackground(themeManager.current.surface)
                                }
                            } header: {
                                Text("Available Models (\(vm.models.count))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(themeManager.current.textSecondary)
                                    .textCase(nil)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Models")
            .onAppear { vm.load() }
        }
    }

    // MARK: - Active Config Card

    private func activeConfigCard(config: CodexConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Active Configuration", systemImage: "star.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Spacer()
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODEL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(themeManager.current.textSecondary)
                        .tracking(0.8)
                    Text(config.model)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeManager.current.textPrimary)
                        .lineLimit(1)
                }

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text("REASONING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(themeManager.current.textSecondary)
                        .tracking(0.8)
                    Text(config.modelReasoningEffort.capitalized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(themeManager.current.accent)
                }

                if !config.mcpServers.isEmpty {
                    Divider()
                        .frame(height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MCP")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(themeManager.current.textSecondary)
                            .tracking(0.8)
                        Text("\(config.mcpServers.count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(themeManager.current.textPrimary)
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeManager.current.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Model Row

    private func modelRow(model: CodexModel) -> some View {
        HStack(spacing: 12) {
            // Active indicator
            ZStack {
                Circle()
                    .fill(model.slug == vm.config?.model
                          ? Color.green.opacity(0.15)
                          : themeManager.current.inputBackground)
                    .frame(width: 36, height: 36)
                Image(systemName: model.slug == vm.config?.model ? "checkmark.circle.fill" : "cpu")
                    .font(.system(size: 16))
                    .foregroundStyle(model.slug == vm.config?.model ? .green : themeManager.current.textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(themeManager.current.textPrimary)
                    if model.slug == vm.config?.model {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.green))
                    }
                }

                if !model.description.isEmpty {
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(themeManager.current.textSecondary)
                        .lineLimit(2)
                }

                if !model.supportedReasoningLevels.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(model.supportedReasoningLevels, id: \.effort) { level in
                            Text(level.effort)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(themeManager.current.accent.opacity(0.12))
                                )
                                .foregroundStyle(themeManager.current.accent)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
