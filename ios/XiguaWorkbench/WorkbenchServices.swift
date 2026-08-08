import Foundation
import CryptoKit
import Observation
import Security
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

enum KeychainStore {
    private static let service = "com.jiangzhichao.xiguaworkbench"
    private static let apiKeyAccount = "deepseek-api-key"
    private static let syncKeyAccount = "workbench-sync-key"

    static func loadAPIKey() -> String {
        load(account: apiKeyAccount)
    }

    static func loadSyncKey() -> String {
        load(account: syncKeyAccount)
    }

    private static func load(account: String) -> String {
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
        try save(key, account: apiKeyAccount)
    }

    static func saveSyncKey(_ key: String) throws {
        try save(key, account: syncKeyAccount)
    }

    private static func save(_ key: String, account: String) throws {
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
        try delete(account: apiKeyAccount)
    }

    static func deleteSyncKey() throws {
        try delete(account: syncKeyAccount)
    }

    private static func delete(account: String) throws {
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

enum WorkbenchSyncStatus: Equatable {
    case local
    case syncing
    case synced
    case error(String)

    var label: String {
        switch self {
        case .local: "当前为本机模式"
        case .syncing: "正在同步…"
        case .synced: "已同步"
        case .error: "同步暂时不可用"
        }
    }
}

@MainActor
@Observable
final class WorkbenchSyncController {
    private static let endpoint = URL(string: "https://xigua-personal-workbench.jone19890801.chatgpt.site/api/sync")!
    private static let lastSyncedKey = "xigua-workbench-last-synced-at-v1"

    private struct CloudTask: Codable {
        let id: String
        let title: String
        let date: String
        let start: String
        let end: String
        let tag: String
        let notes: String
        let done: Bool
        let updatedAt: Int64?
    }

    private struct CloudDiary: Codable {
        let id: String
        let date: String
        let title: String
        let body: String
        let mood: String
        let updatedAt: Int64
    }

    private struct CloudMonthNote: Codable {
        let month: String
        let content: String
        let updatedAt: Int64
    }

    private struct CloudMessage: Codable {
        let id: String
        let role: String
        let content: String
    }

    private struct CloudState: Codable {
        var tasks: [CloudTask]
        var monthlyNotes: [CloudMonthNote]
        var diaries: [CloudDiary]
        var messages: [CloudMessage]
        var diaryMessages: [CloudMessage]
    }

    private struct SyncEnvelope: Codable {
        let state: CloudState?
        let updatedAt: Int64?
        let conflict: Bool?
        let error: String?
    }

    private var preservedMessages: [CloudMessage] = []
    private var preservedDiaryMessages: [CloudMessage] = []

    var status: WorkbenchSyncStatus = .local
    var lastSyncedAt: Date?
    var isConfigured: Bool { KeychainStore.loadSyncKey().count >= 32 }

    init() {
        let milliseconds = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Int64 ?? 0
        if milliseconds > 0 {
            lastSyncedAt = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        }
    }

    func sync(modelContext: ModelContext) async {
        let syncKey = KeychainStore.loadSyncKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard syncKey.count >= 32 else {
            status = .local
            return
        }
        guard status != .syncing else { return }

        status = .syncing
        do {
            let remote = try await fetchRemote(syncKey: syncKey)
            let remoteUpdatedAt = remote.updatedAt ?? 0
            if let state = remote.state {
                preservedMessages = state.messages
                preservedDiaryMessages = state.diaryMessages
                try merge(state, serverUpdatedAt: remoteUpdatedAt, in: modelContext)
            }

            var response = try await pushLocal(
                modelContext: modelContext,
                syncKey: syncKey,
                clientUpdatedAt: remoteUpdatedAt
            )
            if response.conflict == true, let state = response.state {
                let conflictUpdatedAt = response.updatedAt ?? remoteUpdatedAt
                preservedMessages = state.messages
                preservedDiaryMessages = state.diaryMessages
                try merge(state, serverUpdatedAt: conflictUpdatedAt, in: modelContext)
                response = try await pushLocal(
                    modelContext: modelContext,
                    syncKey: syncKey,
                    clientUpdatedAt: conflictUpdatedAt
                )
            }

            let syncedMilliseconds = response.updatedAt ?? remoteUpdatedAt
            if syncedMilliseconds > 0 {
                UserDefaults.standard.set(syncedMilliseconds, forKey: Self.lastSyncedKey)
                lastSyncedAt = Date(timeIntervalSince1970: Double(syncedMilliseconds) / 1_000)
            } else {
                lastSyncedAt = .now
            }
            status = .synced
        } catch {
            status = .error((error as? LocalizedError)?.errorDescription ?? "请稍后再试")
        }
    }

    func disconnect() throws {
        try KeychainStore.deleteSyncKey()
        UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey)
        lastSyncedAt = nil
        status = .local
    }

    private func fetchRemote(syncKey: String) async throws -> SyncEnvelope {
        var request = URLRequest(url: Self.endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        request.setValue(syncKey, forHTTPHeaderField: "x-workbench-sync-key")
        return try await send(request)
    }

    private func pushLocal(
        modelContext: ModelContext,
        syncKey: String,
        clientUpdatedAt: Int64
    ) async throws -> SyncEnvelope {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(syncKey, forHTTPHeaderField: "x-workbench-sync-key")
        request.httpBody = try JSONEncoder().encode([
            "state": AnyEncodable(try cloudState(from: modelContext)),
            "clientUpdatedAt": AnyEncodable(clientUpdatedAt),
        ])
        return try await send(request, acceptsConflict: true)
    }

    private func send(_ request: URLRequest, acceptsConflict: Bool = false) async throws -> SyncEnvelope {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        let envelope = try JSONDecoder().decode(SyncEnvelope.self, from: data)
        if acceptsConflict && http.statusCode == 409 { return envelope }
        guard (200 ... 299).contains(http.statusCode) else {
            throw SyncError.server(envelope.error ?? "云端同步失败")
        }
        return envelope
    }

    private func cloudState(from context: ModelContext) throws -> CloudState {
        let tasks = try context.fetch(FetchDescriptor<WorkbenchTask>())
        let diaries = try context.fetch(FetchDescriptor<DiaryEntry>())
        let notes = try context.fetch(FetchDescriptor<MonthlyNote>())
        return CloudState(
            tasks: tasks.map(cloudTask),
            monthlyNotes: notes.map {
                CloudMonthNote(
                    month: monthKey($0.monthStart),
                    content: $0.content,
                    updatedAt: milliseconds($0.updatedAt)
                )
            },
            diaries: diaries.map {
                CloudDiary(
                    id: $0.id.uuidString.lowercased(),
                    date: dayKey($0.date),
                    title: $0.title,
                    body: $0.body,
                    mood: $0.mood,
                    updatedAt: milliseconds($0.updatedAt)
                )
            },
            messages: preservedMessages,
            diaryMessages: preservedDiaryMessages
        )
    }

    private func cloudTask(_ task: WorkbenchTask) -> CloudTask {
        guard let scheduled = task.scheduledAt else {
            return CloudTask(
                id: task.id.uuidString.lowercased(),
                title: task.title,
                date: "",
                start: "",
                end: "",
                tag: task.tagValue,
                notes: task.detailText,
                done: task.isDone,
                updatedAt: milliseconds(task.updatedAt)
            )
        }
        return CloudTask(
            id: task.id.uuidString.lowercased(),
            title: task.title,
            date: dayKey(scheduled),
            start: timeKey(scheduled),
            end: timeKey(task.scheduledEnd ?? scheduled.addingTimeInterval(3_600)),
            tag: task.tagValue,
            notes: task.detailText,
            done: task.isDone,
            updatedAt: milliseconds(task.updatedAt)
        )
    }

    private func merge(_ state: CloudState, serverUpdatedAt: Int64, in context: ModelContext) throws {
        let checkpoint = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Int64 ?? 0
        let localTasks = try context.fetch(FetchDescriptor<WorkbenchTask>())
        let tasksByID = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })
        for remote in state.tasks {
            let id = UUID(uuidString: remote.id) ?? stableUUID(remote.id)
            let remoteUpdatedAt = remote.updatedAt ?? serverUpdatedAt
            if let local = tasksByID[id] {
                let locallyChanged = milliseconds(local.updatedAt) > checkpoint
                if !locallyChanged || remoteUpdatedAt >= milliseconds(local.updatedAt) {
                    apply(remote, to: local, fallbackUpdatedAt: serverUpdatedAt)
                }
            } else {
                let task = WorkbenchTask(id: id, title: remote.title)
                apply(remote, to: task, fallbackUpdatedAt: serverUpdatedAt)
                context.insert(task)
            }
        }

        let localDiaries = try context.fetch(FetchDescriptor<DiaryEntry>())
        let diariesByID = Dictionary(uniqueKeysWithValues: localDiaries.map { ($0.id, $0) })
        for remote in state.diaries {
            let id = UUID(uuidString: remote.id) ?? stableUUID(remote.id)
            if let local = diariesByID[id] {
                if remote.updatedAt >= milliseconds(local.updatedAt) {
                    apply(remote, to: local)
                }
            } else {
                let entry = DiaryEntry(id: id)
                apply(remote, to: entry)
                context.insert(entry)
            }
        }

        let localNotes = try context.fetch(FetchDescriptor<MonthlyNote>())
        let notesByMonth = Dictionary(uniqueKeysWithValues: localNotes.map { (monthKey($0.monthStart), $0) })
        for remote in state.monthlyNotes {
            guard let month = parseMonth(remote.month) else { continue }
            if let local = notesByMonth[remote.month] {
                if remote.updatedAt >= milliseconds(local.updatedAt) {
                    local.content = remote.content
                    local.updatedAt = date(remote.updatedAt)
                }
            } else {
                context.insert(MonthlyNote(
                    monthStart: month,
                    content: remote.content,
                    updatedAt: date(remote.updatedAt)
                ))
            }
        }
        try context.save()
    }

    private func apply(_ remote: CloudTask, to local: WorkbenchTask, fallbackUpdatedAt: Int64) {
        local.title = remote.title
        local.scheduledAt = parseScheduled(date: remote.date, time: remote.start)
        local.durationMinutes = duration(start: remote.start, end: remote.end)
        local.tag = TaskTag(rawValue: remote.tag) ?? .work
        local.detailText = remote.notes
        local.isDone = remote.done
        local.updatedAt = date(remote.updatedAt ?? fallbackUpdatedAt)
    }

    private func apply(_ remote: CloudDiary, to local: DiaryEntry) {
        local.date = parseDay(remote.date) ?? .now
        local.title = remote.title
        local.body = remote.body
        local.mood = remote.mood
        local.updatedAt = date(remote.updatedAt)
    }

    private func stableUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func parseScheduled(date: String, time: String) -> Date? {
        guard !date.isEmpty, !time.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }

    private func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func parseMonth(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter.date(from: value)
    }

    private func dayKey(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    private func monthKey(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: value)
    }

    private func timeKey(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: value)
    }

    private func duration(start: String, end: String) -> Int {
        func minutes(_ value: String) -> Int? {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] * 60 + parts[1]
        }
        guard let startMinutes = minutes(start), let endMinutes = minutes(end) else { return 60 }
        return max(15, endMinutes - startMinutes)
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }

    enum SyncError: LocalizedError {
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "云端返回了无法识别的内容"
            case .server(let message): message
            }
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeValue = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
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
