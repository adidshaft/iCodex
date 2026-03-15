import Foundation

struct CodexModel: Codable, Identifiable, Equatable {
    let slug: String
    let displayName: String
    let description: String
    let defaultReasoningLevel: String
    let supportedReasoningLevels: [ReasoningLevel]

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, description
        case displayName = "display_name"
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
    }
}

struct ReasoningLevel: Codable, Equatable {
    let effort: String
    let description: String
}

struct CodexConfig: Codable {
    let model: String
    let modelReasoningEffort: String
    let mcpServers: [String: MCPServer]

    enum CodingKeys: String, CodingKey {
        case model
        case modelReasoningEffort = "model_reasoning_effort"
        case mcpServers = "mcp_servers"
    }
}

struct MCPServer: Codable {
    let url: String?
}
