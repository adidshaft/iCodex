import Foundation
import Combine

struct ProjectGroup: Identifiable {
    let id: String  // cwd path
    let name: String
    var threads: [CodexThread]
    var isExpanded: Bool = true

    var hasRunningThread: Bool {
        threads.contains { $0.isRunning }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var serverStatus: ServerStatus?
    @Published var threads: [CodexThread] = []
    @Published var projectGroups: [ProjectGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isServerReachable = false
    @Published var searchText: String = ""
    @Published var showArchived = false

    private var refreshTimer: Timer?
    private let wsService = WebSocketService()

    var filteredGroups: [ProjectGroup] {
        if searchText.isEmpty { return projectGroups }
        let query = searchText.lowercased()
        return projectGroups.compactMap { group in
            let filtered = group.threads.filter {
                $0.title.lowercased().contains(query) ||
                $0.projectName.lowercased().contains(query) ||
                $0.firstUserMessage.lowercased().contains(query) ||
                ($0.gitBranch?.lowercased().contains(query) ?? false)
            }
            if filtered.isEmpty { return nil }
            var g = group
            g.threads = filtered
            return g
        }
    }

    func startPolling() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.refresh() }
        }

        // Connect WebSocket for real-time updates
        wsService.onThreadsUpdate = { [weak self] threads in
            Task { @MainActor [weak self] in
                self?.threads = threads
                self?.buildProjectGroups()
            }
        }
        wsService.connectLive()
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        wsService.disconnect()
    }

    func refresh() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                async let statusReq = APIService.shared.fetchHealth()
                async let threadsReq = APIService.shared.fetchThreads(includeArchived: showArchived)
                let (status, threadsList) = try await (statusReq, threadsReq)
                self.serverStatus = status
                self.threads = threadsList
                self.buildProjectGroups()
                self.isServerReachable = true
            } catch {
                self.isServerReachable = false
                self.errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func toggleGroup(_ groupId: String) {
        if let idx = projectGroups.firstIndex(where: { $0.id == groupId }) {
            projectGroups[idx].isExpanded.toggle()
        }
    }

    private func buildProjectGroups() {
        var groupMap: [String: [CodexThread]] = [:]
        for thread in threads {
            groupMap[thread.cwd, default: []].append(thread)
        }

        // Preserve expansion state
        let oldExpansion = Dictionary(uniqueKeysWithValues: projectGroups.map { ($0.id, $0.isExpanded) })

        projectGroups = groupMap.map { cwd, threads in
            ProjectGroup(
                id: cwd,
                name: (cwd as NSString).lastPathComponent,
                threads: threads.sorted { $0.updatedAt > $1.updatedAt },
                isExpanded: oldExpansion[cwd] ?? true
            )
        }.sorted { g1, g2 in
            // Running projects first, then by most recent update
            if g1.hasRunningThread != g2.hasRunningThread {
                return g1.hasRunningThread
            }
            let max1 = g1.threads.first?.updatedAt ?? 0
            let max2 = g2.threads.first?.updatedAt ?? 0
            return max1 > max2
        }
    }
}
