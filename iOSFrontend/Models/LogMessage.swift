import Foundation

struct LogMessage: Codable, Identifiable, Equatable {
    let id = UUID()
    let type: String
    let data: String
    let taskId: String?

    enum CodingKeys: String, CodingKey {
        case type, data
        case taskId = "task_id"
    }

    static func == (lhs: LogMessage, rhs: LogMessage) -> Bool {
        lhs.id == rhs.id
    }
}
