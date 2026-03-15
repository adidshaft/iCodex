import SwiftUI

struct ModelsView: View {
    @StateObject private var vm = ModelsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading models...")
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.red)
                        Button("Retry") { vm.load() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let config = vm.config {
                            Section("Current Configuration") {
                                HStack {
                                    Label("Active Model", systemImage: "star.fill")
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Text(config.model)
                                        .fontWeight(.semibold)
                                }
                                HStack {
                                    Label("Reasoning Effort", systemImage: "brain")
                                    Spacer()
                                    Text(config.modelReasoningEffort)
                                        .foregroundStyle(.secondary)
                                }
                                if !config.mcpServers.isEmpty {
                                    HStack {
                                        Label("MCP Servers", systemImage: "server.rack")
                                        Spacer()
                                        Text("\(config.mcpServers.count)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        Section("Available Models (\(vm.models.count))") {
                            ForEach(vm.models) { model in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(model.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        if model.slug == vm.config?.model {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                        }
                                    }
                                    if !model.description.isEmpty {
                                        Text(model.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !model.supportedReasoningLevels.isEmpty {
                                        HStack(spacing: 6) {
                                            ForEach(model.supportedReasoningLevels, id: \.effort) { level in
                                                Text(level.effort)
                                                    .font(.system(size: 10))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        Capsule()
                                                            .fill(Color.blue.opacity(0.1))
                                                    )
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Models")
            .onAppear { vm.load() }
        }
    }
}
