import Foundation
import Observation

@MainActor
@Observable
final class WorkbenchStore {
    private(set) var tasks: [WorkbenchTask] = []
    private(set) var diaryEntries: [DiaryEntry] = []
    private(set) var monthlyNotes: [String: String] = [:]
    private(set) var lastSavedAt: Date?
    var notice: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    var openTasks: [WorkbenchTask] {
        tasks.filter { !$0.isCompleted }
    }

    var completedTasks: [WorkbenchTask] {
        tasks.filter(\.isCompleted)
    }

    func tasks(on date: Date) -> [WorkbenchTask] {
        let day = Calendar.current.startOfDay(for: date)
        return tasks
            .filter { task in
                guard let taskDate = task.date else { return false }
                return Calendar.current.isDate(taskDate, inSameDayAs: day)
            }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                return lhs.startMinute < rhs.startMinute
            }
    }

    func tasks(in month: Date) -> [WorkbenchTask] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return tasks.filter { task in
            guard let date = task.date else { return false }
            return interval.contains(date)
        }
    }

    func upcomingTasks(from date: Date, days: Int = 14) -> [WorkbenchTask] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        return tasks
            .filter { task in
                guard let taskDate = task.date else { return false }
                return taskDate >= start && taskDate < end
            }
            .sorted {
                if $0.date != $1.date { return ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
                return $0.startMinute < $1.startMinute
            }
    }

    func task(id: UUID) -> WorkbenchTask? {
        tasks.first { $0.id == id }
    }

    func upsert(_ task: WorkbenchTask) {
        var normalized = task
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.title.isEmpty else { return }
        normalized.date = normalized.date.map { Calendar.current.startOfDay(for: $0) }
        normalized.endMinute = max(normalized.endMinute, normalized.startMinute + 15)

        if let index = tasks.firstIndex(where: { $0.id == normalized.id }) {
            tasks[index] = normalized
        } else {
            tasks.append(normalized)
        }
        persist(message: "任务已保存")
    }

    func addQuickTask(title: String, date: Date?) {
        upsert(WorkbenchTask(title: title, date: date))
    }

    func toggleTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted.toggle()
        persist(message: tasks[index].isCompleted ? "已完成" : "已恢复")
    }

    func moveTask(_ id: UUID, to date: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].date = date.map { Calendar.current.startOfDay(for: $0) }
        persist(message: date == nil ? "已放入待办箱" : "已安排日期")
    }

    func deleteTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        persist(message: "任务已删除")
    }

    func diary(id: UUID) -> DiaryEntry? {
        diaryEntries.first { $0.id == id }
    }

    func upsert(_ diary: DiaryEntry) {
        var normalized = diary
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.updatedAt = .now
        if normalized.title.isEmpty {
            normalized.title = DateFormatting.longDate.string(from: normalized.date)
        }

        if let index = diaryEntries.firstIndex(where: { $0.id == normalized.id }) {
            diaryEntries[index] = normalized
        } else {
            diaryEntries.append(normalized)
        }
        diaryEntries.sort { $0.date > $1.date }
        persist(message: "日记已保存")
    }

    func deleteDiary(_ id: UUID) {
        diaryEntries.removeAll { $0.id == id }
        persist(message: "日记已删除")
    }

    func monthPlan(for key: String) -> String {
        monthlyNotes[key] ?? ""
    }

    func setMonthPlan(_ content: String, for key: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            monthlyNotes.removeValue(forKey: key)
        } else {
            monthlyNotes[key] = content
        }
        persist(message: "月度计划已保存")
    }

    func deleteCompletedTasks() {
        tasks.removeAll( where: \.isCompleted)
        persist(message: "已清理完成任务")
    }

    func exportData() throws -> Data {
        try JSONEncoder.pretty.encode(makeBackup())
    }

    func importData(_ data: Data) throws {
        let backup = try JSONDecoder().decode(WorkbenchBackup.self, from: data)
        apply(backup)
        persist(message: "备份已导入")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let backup = try JSONDecoder().decode(WorkbenchBackup.self, from: data)
            apply(backup)
        } catch {
            notice = "本机数据读取失败，已保留原文件。"
        }
    }

    private func persist(message: String? = nil) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder.pretty.encode(makeBackup()).write(to: fileURL, options: .atomic)
            lastSavedAt = .now
            notice = message
        } catch {
            notice = "保存失败：\(error.localizedDescription)"
        }
    }

    private func makeBackup() -> WorkbenchBackup {
        WorkbenchBackup(
            tasks: tasks.map { task in
                WebTaskPayload(
                    id: task.id.uuidString,
                    title: task.title,
                    date: task.date.map(DateFormatting.dateKey.string) ?? "",
                    start: WorkbenchTask.timeText(task.startMinute),
                    end: WorkbenchTask.timeText(task.endMinute),
                    tag: task.tag.rawValue,
                    notes: task.notes,
                    done: task.isCompleted
                )
            },
            monthlyNotes: monthlyNotes.map { key, content in
                WebMonthNotePayload(month: key, content: content, updatedAt: Date.now.timeIntervalSince1970 * 1000)
            },
            diaries: diaryEntries.map { diary in
                WebDiaryPayload(
                    id: diary.id.uuidString,
                    date: DateFormatting.dateKey.string(from: diary.date),
                    title: diary.title,
                    body: diary.body,
                    mood: diary.mood,
                    updatedAt: diary.updatedAt.timeIntervalSince1970 * 1000
                )
            }
        )
    }

    private func apply(_ backup: WorkbenchBackup) {
        tasks = backup.tasks.map { payload in
            WorkbenchTask(
                id: UUID(uuidString: payload.id) ?? UUID(),
                title: payload.title,
                date: payload.date.isEmpty ? nil : DateFormatting.dateKey.date(from: payload.date),
                startMinute: DateFormatting.minute(from: payload.start, fallback: 9 * 60),
                endMinute: DateFormatting.minute(from: payload.end, fallback: 10 * 60),
                tag: TaskTag(rawValue: payload.tag) ?? .work,
                notes: payload.notes,
                isCompleted: payload.done
            )
        }
        monthlyNotes = Dictionary(uniqueKeysWithValues: backup.monthlyNotes.map { ($0.month, $0.content) })
        diaryEntries = backup.diaries.map { payload in
            DiaryEntry(
                id: UUID(uuidString: payload.id) ?? UUID(),
                date: DateFormatting.dateKey.date(from: payload.date) ?? .now,
                title: payload.title,
                body: payload.body,
                mood: payload.mood,
                updatedAt: Date(timeIntervalSince1970: payload.updatedAt / 1000)
            )
        }.sorted { $0.date > $1.date }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("西瓜老师工作台", isDirectory: true)
            .appendingPathComponent("workbench.json")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
