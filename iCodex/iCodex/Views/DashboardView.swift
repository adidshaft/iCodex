import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.threads.isEmpty {
                    ProgressView("Connecting...")
                } else if !vm.isServerReachable {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Server Unreachable")
                            .font(.headline)
                        if let msg = vm.errorMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Button("Retry") { vm.refresh() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let status = vm.serverStatus, let stats = status.stats {
                            Section("Overview") {
                                HStack {
                                    Label("Running", systemImage: "bolt.fill")
                                        .foregroundStyle(.green)
                                    Spacer()
                                    Text("\(stats.runningThreads)")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.green)
                                }
                                HStack {
                                    Label("Threads", systemImage: "bubble.left.and.bubble.right")
                                    Spacer()
                                    Text("\(stats.activeThreads)")
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Label("Total Tokens", systemImage: "number")
                                    Spacer()
                                    Text(stats.formattedTotalTokens)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

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
                                    }
                                }
                            } header: {
                                Button {
                                    vm.toggleGroup(group.id)
                                } label: {
                                    HStack {
                                        Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(.blue)
                                        Text(group.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        if group.hasRunningThread {
                                            PulsingDot()
                                        }
                                        Spacer()
                                        Text("\(group.threads.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .refreshable { vm.refresh() }
                    .searchable(text: $vm.searchText, prompt: "Search threads...")
                }
            }
            .navigationTitle("iCodex")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.showArchived.toggle()
                        vm.refresh()
                    } label: {
                        Image(systemName: vm.showArchived ? "archivebox.fill" : "archivebox")
                    }
                }
            }
            .onAppear { vm.startPolling() }
            .onDisappear { vm.stopPolling() }
        }
    }
}
