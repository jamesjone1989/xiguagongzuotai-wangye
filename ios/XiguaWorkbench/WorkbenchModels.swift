import Foundation
import SwiftData

enum TaskTag: String, CaseIterable, Codable, Identifiable {
    case work = "工作"
    case life = "生活"
    case important = "重要"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .work: "briefcase.fill"
        case .life: "leaf.fill"
        case .important: "exclamationmark.circle.fill"
        }
    }
}

@Model
final class WorkbenchTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var scheduledAt: Date?
    var durationMinutes: Int
    var tagValue: String
    var detailText: String
    var isDone: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        scheduledAt: Date? = nil,
        durationMinutes: Int = 60,
        tag: TaskTag = .work,
        detailText: String = "",
        isDone: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes
        self.tagValue = tag.rawValue
        self.detailText = detailText
        self.isDone = isDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var tag: TaskTag {
        get { TaskTag(rawValue: tagValue) ?? .work }
        set { tagValue = newValue.rawValue }
    }

    var scheduledEnd: Date? {
        scheduledAt?.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

@Model
final class DiaryEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var title: String
    var body: String
    var mood: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String = "",
        body: String = "",
        mood: String = "平静",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.mood = mood
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MonthlyNote {
    @Attribute(.unique) var id: UUID
    var monthStart: Date
    var content: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        monthStart: Date,
        content: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthStart = monthStart.startOfMonth
        self.content = content
        self.updatedAt = updatedAt
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? startOfDay
    }

    var startOfWeek: Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? startOfDay
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }

    static func combining(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        var result = DateComponents()
        result.year = dayParts.year
        result.month = dayParts.month
        result.day = dayParts.day
        result.hour = timeParts.hour
        result.minute = timeParts.minute
        return calendar.date(from: result) ?? day
    }
}

extension Date.FormatStyle {
    static var chineseDay: Date.FormatStyle {
        Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "zh_CN"))
    }

    static var chineseMonth: Date.FormatStyle {
        Date.FormatStyle().year().month(.wide).locale(Locale(identifier: "zh_CN"))
    }
}

struct TaskEditorRoute: Identifiable {
    let id = UUID()
    let task: WorkbenchTask?
    let defaultDate: Date?
}

struct DiaryEditorRoute: Identifiable {
    let id = UUID()
    let entry: DiaryEntry?
    let initialTitle: String
    let initialBody: String

    init(entry: DiaryEntry?, initialTitle: String = "", initialBody: String = "") {
        self.entry = entry
        self.initialTitle = initialTitle
        self.initialBody = initialBody
    }
}
