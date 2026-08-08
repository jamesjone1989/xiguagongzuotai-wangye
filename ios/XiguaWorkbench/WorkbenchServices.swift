import Foundation
import Security
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

enum KeychainStore {
    private static let service = "com.jiangzhichao.xiguaworkbench"
    private static let account = "deepseek-api-key"

    static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func saveAPIKey(_ key: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let value = Data(key.utf8)
        let status = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: value] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = lookup
            item[kSecValueData as String] = value
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? { "钥匙串操作失败，请稍后重试。" }
    }
}

enum DeepSeekService {
    struct ParsedTask: Decodable {
        let title: String
        let date: String?
        let start: String?
        let durationMinutes: Int?
        let tag: String?
        let notes: String?
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ResponseFormat: Encodable {
        let type = "json_object"
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let responseFormat: ResponseFormat?
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages
            case responseFormat = "response_format"
            case maxTokens = "max_tokens"
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct AssistantMessage: Decodable { let content: String? }
            let message: AssistantMessage
        }
        let choices: [Choice]
    }

    static func parseTask(_ text: String, apiKey: String, now: Date = .now) async throws -> ParsedTask {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: now)
        let prompt = """
        今天是 \(today)。把用户输入整理成一个任务，并只输出 JSON：
        {"title":"任务标题","date":"YYYY-MM-DD 或 null","start":"HH:mm 或 null","durationMinutes":60,"tag":"工作/生活/重要","notes":"补充说明"}
        没有明确日期或时间时不要猜，date 或 start 写 null。durationMinutes 取 15 到 480。
        用户输入：\(text)
        """
        let content = try await chat(
            system: "你是个人工作台的任务整理助手。必须输出合法 JSON，不添加解释。",
            user: prompt,
            apiKey: apiKey,
            json: true,
            maxTokens: 500
        )
        guard let data = content.data(using: .utf8) else { throw ServiceError.invalidResponse }
        return try JSONDecoder().decode(ParsedTask.self, from: data)
    }

    static func polishDiary(_ text: String, apiKey: String) async throws -> String {
        try await chat(
            system: "你是克制的中文日记编辑。保留事实和第一人称，不虚构细节，不添加说教。",
            user: "请整理下面这段日记，保留原意并改善表达，只返回正文：\n\n\(text)",
            apiKey: apiKey,
            json: false,
            maxTokens: 1400
        )
    }

    private static func chat(
        system: String,
        user: String,
        apiKey: String,
        json: Bool,
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw ServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: "system", content: system), Message(role: "user", content: user)],
            responseFormat: json ? ResponseFormat() : nil,
            maxTokens: maxTokens
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw ServiceError.http(httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw ServiceError.invalidResponse
        }
        return content
    }

    enum ServiceError: LocalizedError {
        case invalidResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "AI 返回的内容暂时无法使用，请重试。"
            case .http(401): "API Key 无效，请到设置中检查。"
            case .http(402): "DeepSeek 账户余额不足。"
            case .http(429): "请求过于频繁，请稍后再试。"
            case .http: "AI 服务暂时不可用，请稍后再试。"
            }
        }
    }
}

struct WorkbenchBackup: Codable {
    struct TaskRecord: Codable {
        let id: UUID
        let title: String
        let scheduledAt: Date?
        let durationMinutes: Int
        let tag: String
        let detailText: String
        let isDone: Bool
        let createdAt: Date
        let updatedAt: Date
    }

    struct DiaryRecord: Codable {
        let id: UUID
        let date: Date
        let title: String
        let body: String
        let mood: String
        let createdAt: Date
        let updatedAt: Date
    }

    struct MonthRecord: Codable {
        let id: UUID
        let monthStart: Date
        let content: String
        let updatedAt: Date
    }

    let version: Int
    let exportedAt: Date
    let tasks: [TaskRecord]
    let diaries: [DiaryRecord]
    let monthlyNotes: [MonthRecord]
}

struct WorkbenchBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    static func encode(tasks: [WorkbenchTask], diaries: [DiaryEntry], notes: [MonthlyNote]) throws -> Data {
        let backup = WorkbenchBackup(
            version: 1,
            exportedAt: .now,
            tasks: tasks.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    scheduledAt: $0.scheduledAt,
                    durationMinutes: $0.durationMinutes,
                    tag: $0.tagValue,
                    detailText: $0.detailText,
                    isDone: $0.isDone,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            diaries: diaries.map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    title: $0.title,
                    body: $0.body,
                    mood: $0.mood,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            monthlyNotes: notes.map {
                .init(id: $0.id, monthStart: $0.monthStart, content: $0.content, updatedAt: $0.updatedAt)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> WorkbenchBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchBackup.self, from: data)
    }

    @MainActor
    static func restore(_ backup: WorkbenchBackup, in context: ModelContext) throws {
        try context.delete(model: WorkbenchTask.self)
        try context.delete(model: DiaryEntry.self)
        try context.delete(model: MonthlyNote.self)

        backup.tasks.forEach {
            context.insert(WorkbenchTask(
                id: $0.id,
                title: $0.title,
                scheduledAt: $0.scheduledAt,
                durationMinutes: $0.durationMinutes,
                tag: TaskTag(rawValue: $0.tag) ?? .work,
                detailText: $0.detailText,
                isDone: $0.isDone,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            ))
        }
        backup.diaries.forEach {
            context.insert(DiaryEntry(
                id: $0.id,
                date: $0.date,
                title: $0.title,
                body: $0.body,
                mood: $0.mood,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt
            ))
        }
        backup.monthlyNotes.forEach {
            context.insert(MonthlyNote(
                id: $0.id,
                monthStart: $0.monthStart,
                content: $0.content,
                updatedAt: $0.updatedAt
            ))
        }
        try context.save()
    }
}
