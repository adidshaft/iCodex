import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.threads.isEmpty {
                    loadingView
                } else if !vm.isServerReachable {
                    serverUnreachableView
                } else {
                    mainContent
                }
            }
            .navigationTitle("iCodex")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.showArchived.toggle()
                        vm.refresh()
                    } label: {
                        Image(systemName: vm.showArchived ? "archivebox.fill" : "archivebox")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(themeManager.current.accent)
                    }
                }
            }
            .onAppear { vm.startPolling() }
            .onDisappear { vm.stopPolling() }
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(themeManager.current.accent)
            Text("Connecting to iCodex...")
                .font(.subheadline)
                .foregroundStyle(themeManager.current.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }

    // MARK: - Server Unreachable State

    private var serverUnreachableView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 6) {
                Text("Server Unreachable")
                    .font(.headline)
                    .foregroundStyle(themeManager.current.textPrimary)
                if let msg = vm.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(themeManager.current.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Button {
                vm.refresh()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(themeManager.current.accent.opacity(0.15)))
                    .foregroundStyle(themeManager.current.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            themeManager.current.background.ignoresSafeArea()

            List {
                // Stats Cards Section
                if let status = vm.serverStatus, let stats = status.stats {
                    Section {
                        statsCardsRow(stats: stats)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                // Thread Groups
                ForEach(vm.filteredGroups) { group in
                    Section {
                        if group.isExpanded {
                            ForEach(group.threads) { thread in
                                NavigationLink(destination: ThreadDetailView(threadId: thread.id)) {
                                    ThreadRowView(thread: thread)
                                }
                                .swipeActions(edge: .trailing) {
                                    if thread.isRunning {
                                        Button(role: .destructive) {
                                            vm.stopThread(thread.id)
                                        } label: {
                                            Label("Stop", systemImage: "stop.fill")
                                        }
                                    }
                                }
                                .listRowBackground(themeManager.current.surface)
                            }
                        }
                    } header: {
                        groupHeader(group: group)
                    }
                }

                // Empty state
                if vm.filteredGroups.isEmpty && !vm.isLoading {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundStyle(themeManager.current.textSecondary.opacity(0.5))
                            Text("No threads yet")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.current.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable { vm.refresh() }
            .searchable(text: $vm.searchText, prompt: "Search threads...")
        }
    }

    // MARK: - Stats Cards Row

    @ViewBuilder
    private func statsCardsRow(stats: ThreadStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                statCard(
                    value: "\(stats.runningThreads)",
                    label: "Running",
                    icon: "bolt.fill",
                    iconColor: .green,
                    highlight: stats.runningThreads > 0
                )
                statCard(
                    value: "\(stats.activeThreads)",
                    label: "Threads",
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: themeManager.current.accent,
                    highlight: false
                )
                statCard(
                    value: stats.formattedTotalTokens,
                    label: "Tokens",
                    icon: "number.circle.fill",
                    iconColor: Color(red: 0.7, green: 0.4, blue: 0.9),
                    highlight: false
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func statCard(value: String, label: String, icon: String, iconColor: Color, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                Spacer()
                if highlight {
                    PulsingDot()
                }
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(themeManager.current.textPrimary)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(themeManager.current.textSecondary)
                .tracking(0.8)
        }
        .padding(14)
        .frame(width: 112)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeManager.current.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(themeManager.current.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Group Header

    private func groupHeader(group: ProjectGroup) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                vm.toggleGroup(group.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeManager.current.textSecondary)
                    .frame(width: 14)

                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(themeManager.current.accent)

                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(themeManager.current.textPrimary)
                    .lineLimit(1)

                if group.hasRunningThread {
                    PulsingDot()
                }

                Spacer()

                Text("\(group.threads.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeManager.current.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(themeManager.current.inputBackground)
                    )
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }
}
