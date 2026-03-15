import Foundation

struct ThreadStats: Codable {
    let totalThreads: Int
    let activeThreads: Int
    let archivedThreads: Int
    let totalTokensUsed: Int
    let runningThreads: Int
    let sources: [String: Int]

    enum CodingKeys: String, CodingKey {
        case totalThreads = "total_threads"
        case activeThreads = "active_threads"
        case archivedThreads = "archived_threads"
        case totalTokensUsed = "total_tokens_used"
        case runningThreads = "running_threads"
        case sources
    }

    var formattedTotalTokens: String {
        if totalTokensUsed >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokensUsed) / 1_000_000)
        } else if totalTokensUsed >= 1_000 {
            return String(format: "%.1fK", Double(totalTokensUsed) / 1_000)
        }
        return "\(totalTokensUsed)"
    }
}

struct ServerStatus: Codable {
    let status: String
    let version: String
    let stats: ThreadStats?
    let uptimeSeconds: Double

    enum CodingKeys: String, CodingKey {
        case status, version, stats
        case uptimeSeconds = "uptime_seconds"
    }

    var formattedUptime: String {
        let h = Int(uptimeSeconds) / 3600
        let m = (Int(uptimeSeconds) % 3600) / 60
        let s = Int(uptimeSeconds) % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
