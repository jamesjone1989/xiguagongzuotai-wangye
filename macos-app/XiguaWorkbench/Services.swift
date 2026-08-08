import Foundation
import Security

enum KeychainStore {
    private static let service = "com.jiangzhichao.xigua-workbench"
    private static let account = "deepseek-api-key"
    private static let syncAccount = "cross-platform-sync-key"

    static func readDeepSeekKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    static func saveDeepSeekKey(_ value: String) throws {
        try save(value, account: account)
    }

    static func readSyncKey() -> String {
        read(account: syncAccount)
    }

    static func saveSyncKey(_ value: String) throws {
        try save(value, account: syncAccount)
    }

    private static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    private static func save(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if trimmed.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(newItem as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }
}

struct RemoteSyncState: Sendable {
    let stateData: Data?
    let updatedAt: Double
}

actor CrossPlatformSyncService {
    static let shared = CrossPlatformSyncService()
    private let endpoint = URL(string: "https://xigua-personal-workbench.jone19890801.chatgpt.site/api/sync")!

    func fetch(syncKey: String) async throws -> RemoteSyncState {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(syncKey, forHTTPHeaderField: "x-workbench-sync-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updatedAt = object?["updatedAt"] as? Double ?? 0
        let stateData: Data?
        if let value = object?["state"], !(value is NSNull) {
            stateData = try? JSONSerialization.data(withJSONObject: value)
        } else {
            stateData = nil
        }
        return RemoteSyncState(stateData: stateData, updatedAt: updatedAt)
    }

    func push(stateData: Data, syncKey: String, clientUpdatedAt: Double) async throws -> Double {
        let state = try JSONSerialization.jsonObject(with: stateData)
        let body: [String: Any] = ["state": state, "clientUpdatedAt": clientUpdatedAt]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(syncKey, forHTTPHeaderField: "x-workbench-sync-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["updatedAt"] as? Double ?? Date.now.timeIntervalSince1970 * 1000
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SyncError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw SyncError.server(object?["error"] as? String ?? "同步服务暂时不可用")
        }
    }
}

enum SyncError: LocalizedError {
    case unavailable
    case server(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "没有连接上跨平台同步服务。"
        case .server(let message): message
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "钥匙串保存失败（\(status)）"
    }
}

struct ExtractedTask: Sendable {
    let title: String
    let date: Date?
    let startMinute: Int
    let endMinute: Int
    let tag: TaskTag
    let notes: String

    var workbenchTask: WorkbenchTask {
        WorkbenchTask(
            title: title,
            date: date,
            startMinute: startMinute,
            endMinute: endMinute,
            tag: tag,
            notes: notes
        )
    }
}

struct GeneratedDiary: Sendable {
    let title: String
    let body: String
}

struct WeeklyBriefGroup: Codable, Identifiable, Sendable {
    var id: String { title }
    let title: String
    let items: [String]
}

struct WeeklyBriefAnalysis: Codable, Sendable {
    let summary: String
    let groups: [WeeklyBriefGroup]
    let nextFocus: String
}

actor DeepSeekService {
    static let shared = DeepSeekService()
    private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    private let model = "deepseek-v4-flash"

    func extractTasks(from text: String, selectedDate: Date, apiKey: String) async throws -> [ExtractedTask] {
        let today = DateFormatting.dateKey.string(from: selectedDate)
        let system = """
        把用户文字提取为待办任务。今天选择的是 \(today)。只能使用用户明确说出的信息，不得猜测日期或时间。
        每项必须返回 hasExplicitDate 和 hasExplicitTime。只有用户明确说出日期并且明确说出时间时，date/start/end 才用于日程；否则任务先进入待办箱，date、start、end 均返回空字符串。
        “今天、明天、后天、下周几”属于明确日期；“上午十点、15:30”属于明确时间。没有结束时间时按一小时计算。
        tag 只能是 工作、生活、重要。只输出 JSON：
        {"tasks":[{"title":"任务标题","date":"YYYY-MM-DD或空","start":"HH:mm或空","end":"HH:mm或空","tag":"工作|生活|重要","notes":"补充","hasExplicitDate":true,"hasExplicitTime":true}]}
        """
        let content = try await complete(apiKey: apiKey, messages: [
            APIMessage(role: "system", content: system),
            APIMessage(role: "user", content: text),
        ], json: true, maxTokens: 900)
        let decoded = try JSONDecoder().decode(TaskExtractionResponse.self, from: Data(cleanJSON(content).utf8))
        return decoded.tasks.compactMap { item in
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let scheduled = item.hasExplicitDate && item.hasExplicitTime
            let date = scheduled ? DateFormatting.dateKey.date(from: item.date) : nil
            let start = scheduled ? DateFormatting.minute(from: item.start, fallback: 9 * 60) : 9 * 60
            let rawEnd = scheduled ? DateFormatting.minute(from: item.end, fallback: start + 60) : 10 * 60
            return ExtractedTask(
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                startMinute: start,
                endMinute: max(rawEnd, start + 15),
                tag: TaskTag(rawValue: item.tag) ?? .work,
                notes: item.notes
            )
        }
    }

    func diaryReply(messages: [ChatMessage], apiKey: String) async throws -> String {
        let system = "你是西瓜老师，帮助用户把今天发生的事聊清楚，之后整理成日记。每次只回复一句简短具体的话，优先问发生了什么、接下来发生了什么、最后结果怎样。不要诊断、夸奖、说教或编造信息。"
        let recent = messages.suffix(16).map { APIMessage(role: $0.role, content: $0.content) }
        return try await complete(
            apiKey: apiKey,
            messages: [APIMessage(role: "system", content: system)] + recent,
            json: false,
            maxTokens: 220
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func generateDiary(messages: [ChatMessage], apiKey: String) async throws -> GeneratedDiary {
        let transcript = messages.map { "\($0.role == "assistant" ? "西瓜老师" : "我")：\($0.content)" }.joined(separator: "\n")
        let system = """
        把对话整理为第一人称中文日记，只能使用明确出现或可直接推断的信息。不要编造人物、地点、情节、时间、因果或心理活动。语言自然克制，素材少就写短。
        只输出 JSON：{"title":"24字以内标题","paragraphs":["段落1","段落2"],"takeaway":"30字以内今日所得"}
        """
        let content = try await complete(apiKey: apiKey, messages: [
            APIMessage(role: "system", content: system),
            APIMessage(role: "user", content: transcript),
        ], json: true, maxTokens: 1000)
        let value = try JSONDecoder().decode(DiaryGenerationResponse.self, from: Data(cleanJSON(content).utf8))
        let body = (value.paragraphs + (value.takeaway.isEmpty ? [] : ["今日所得：\(value.takeaway)"])).joined(separator: "\n\n")
        return GeneratedDiary(title: value.title, body: body)
    }

    func generateWeeklyBrief(taskMaterial: String, apiKey: String) async throws -> WeeklyBriefAnalysis {
        let system = """
        把本周任务按实际工作主题归类整理成管理者可快速阅读的中文简报。只能使用用户提供的任务，不得编造完成情况、原因、人物或结果。
        分类名称要具体，例如“项目推进”“培训与人才发展”“沟通协调”，不要机械地按完成/未完成分类。相近任务合并表达，每项一句。
        只输出 JSON：{"summary":"本周整体概况","groups":[{"title":"分类名称","items":["事项1","事项2"]}],"nextFocus":"下周最值得继续推进的重点"}
        """
        let content = try await complete(apiKey: apiKey, messages: [
            APIMessage(role: "system", content: system),
            APIMessage(role: "user", content: taskMaterial),
        ], json: true, maxTokens: 1200)
        return try JSONDecoder().decode(WeeklyBriefAnalysis.self, from: Data(cleanJSON(content).utf8))
    }

    private func complete(apiKey: String, messages: [APIMessage], json: Bool, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(APIRequest(
            model: model,
            messages: messages,
            thinking: Thinking(type: "disabled"),
            maxTokens: maxTokens,
            responseFormat: json ? ResponseFormat(type: "json_object") : nil
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeepSeekError.requestFailed
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw DeepSeekError.emptyResponse
        }
        return content
    }

    private func cleanJSON(_ value: String) -> String {
        value.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
    }
}

enum DeepSeekError: LocalizedError {
    case requestFailed
    case emptyResponse
    var errorDescription: String? {
        switch self {
        case .requestFailed: "DeepSeek 请求失败，请检查 API Key 或网络。"
        case .emptyResponse: "DeepSeek 没有返回可用内容。"
        }
    }
}

private struct APIMessage: Codable, Sendable { let role: String; let content: String }
private struct Thinking: Codable, Sendable { let type: String }
private struct ResponseFormat: Codable, Sendable { let type: String }
private struct APIRequest: Codable, Sendable {
    let model: String
    let messages: [APIMessage]
    let thinking: Thinking
    let maxTokens: Int
    let responseFormat: ResponseFormat?
    enum CodingKeys: String, CodingKey {
        case model, messages, thinking
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}
private struct APIResponse: Codable, Sendable {
    struct Choice: Codable, Sendable { let message: APIMessage }
    let choices: [Choice]
}
private struct TaskExtractionResponse: Codable, Sendable { let tasks: [TaskExtractionItem] }
private struct TaskExtractionItem: Codable, Sendable {
    let title: String
    let date: String
    let start: String
    let end: String
    let tag: String
    let notes: String
    let hasExplicitDate: Bool
    let hasExplicitTime: Bool
}
private struct DiaryGenerationResponse: Codable, Sendable {
    let title: String
    let paragraphs: [String]
    let takeaway: String
}
