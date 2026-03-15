import Foundation

struct GitStats: Codable, Equatable {
    let insertions: Int
    let deletions: Int
    let filesChanged: Int

    enum CodingKeys: String, CodingKey {
        case insertions, deletions
        case filesChanged = "files_changed"
    }
}

struct CodexThread: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    let modelProvider: String
    let cwd: String
    let createdAt: Int
    let updatedAt: Int
    let approvalMode: String
    let tokensUsed: Int
    let archived: Bool
    let gitBranch: String?
    let gitOriginUrl: String?
    let cliVersion: String
    let firstUserMessage: String
    let agentNickname: String?
    let isRunning: Bool
    let gitStats: GitStats?

    enum CodingKeys: String, CodingKey {
        case id, title, source, cwd, archived
        case modelProvider = "model_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case approvalMode = "approval_mode"
        case tokensUsed = "tokens_used"
        case gitBranch = "git_branch"
        case gitOriginUrl = "git_origin_url"
        case cliVersion = "cli_version"
        case firstUserMessage = "first_user_message"
        case agentNickname = "agent_nickname"
        case isRunning = "is_running"
        case gitStats = "git_stats"
    }

    var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(updatedAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var sourceIcon: String {
        switch source {
        case "vscode": return "chevron.left.forwardslash.chevron.right"
        case "terminal": return "terminal"
        default: return "desktopcomputer"
        }
    }

    var formattedTokens: String {
        if tokensUsed >= 1_000_000 {
            return String(format: "%.1fM", Double(tokensUsed) / 1_000_000)
        } else if tokensUsed >= 1_000 {
            return String(format: "%.1fK", Double(tokensUsed) / 1_000)
        }
        return "\(tokensUsed)"
    }
}

struct ThreadDetail: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    let modelProvider: String
    let cwd: String
    let createdAt: Int
    let updatedAt: Int
    let approvalMode: String
    let tokensUsed: Int
    let archived: Bool
    let gitBranch: String?
    let gitOriginUrl: String?
    let cliVersion: String
    let firstUserMessage: String
    let agentNickname: String?
    let rolloutPath: String
    let sandboxPolicy: String
    let gitSha: String?
    let agentRole: String?
    let memoryMode: String
    let isRunning: Bool
    let gitStats: GitStats?

    enum CodingKeys: String, CodingKey {
        case id, title, source, cwd, archived
        case modelProvider = "model_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case approvalMode = "approval_mode"
        case tokensUsed = "tokens_used"
        case gitBranch = "git_branch"
        case gitOriginUrl = "git_origin_url"
        case cliVersion = "cli_version"
        case firstUserMessage = "first_user_message"
        case agentNickname = "agent_nickname"
        case rolloutPath = "rollout_path"
        case sandboxPolicy = "sandbox_policy"
        case gitSha = "git_sha"
        case agentRole = "agent_role"
        case memoryMode = "memory_mode"
        case isRunning = "is_running"
        case gitStats = "git_stats"
    }

    var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(updatedAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var projectName: String {
        (cwd as NSString).lastPathComponent
    }

    var formattedTokens: String {
        if tokensUsed >= 1_000_000 {
            return String(format: "%.1fM", Double(tokensUsed) / 1_000_000)
        } else if tokensUsed >= 1_000 {
            return String(format: "%.1fK", Double(tokensUsed) / 1_000)
        }
        return "\(tokensUsed)"
    }
}

struct ConversationMessage: Codable, Identifiable, Equatable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: String?
    let type: String

    enum CodingKeys: String, CodingKey {
        case role, content, timestamp, type
    }

    static func == (lhs: ConversationMessage, rhs: ConversationMessage) -> Bool {
        lhs.id == rhs.id
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isDeveloper: Bool { role == "developer" }
    var isSystem: Bool { role == "system" }
}
