import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today
    case month
    case year
    case agenda
    case inbox
    case diary
    case brief
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .month: "月历"
        case .year: "年历"
        case .agenda: "日程"
        case .inbox: "待办箱"
        case .diary: "日记"
        case .brief: "简报"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .month: "calendar"
        case .year: "square.grid.3x3"
        case .agenda: "clock"
        case .inbox: "tray"
        case .diary: "book.closed"
        case .brief: "chart.bar.doc.horizontal"
        case .settings: "gearshape"
        }
    }
}

enum TaskTag: String, CaseIterable, Codable, Identifiable, Sendable {
    case work = "工作"
    case life = "生活"
    case important = "重要"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .work: "briefcase"
        case .life: "leaf"
        case .important: "exclamationmark"
        }
    }
}

struct WorkbenchTask: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var date: Date?
    var startMinute: Int
    var endMinute: Int
    var tag: TaskTag
    var notes: String
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        date: Date? = nil,
        startMinute: Int = 9 * 60,
        endMinute: Int = 10 * 60,
        tag: TaskTag = .work,
        notes: String = "",
        isCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.date = date.map { Calendar.current.startOfDay(for: $0) }
        self.startMinute = startMinute
        self.endMinute = max(endMinute, startMinute + 15)
        self.tag = tag
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    var timeRangeText: String? {
        guard date != nil else { return nil }
        return "\(Self.timeText(startMinute))–\(Self.timeText(endMinute))"
    }

    static func timeText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

struct DiaryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var title: String
    var body: String
    var mood: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String = "",
        body: String = "",
        mood: String = "平静",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.title = title
        self.body = body
        self.mood = mood
        self.updatedAt = updatedAt
    }
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: String
    var content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct WebTaskPayload: Codable {
    var id: String
    var title: String
    var date: String
    var start: String
    var end: String
    var tag: String
    var notes: String
    var done: Bool
}

struct WebMonthNotePayload: Codable {
    var month: String
    var content: String
    var updatedAt: Double
}

struct WebDiaryPayload: Codable {
    var id: String
    var date: String
    var title: String
    var body: String
    var mood: String
    var updatedAt: Double
}

struct WebMessagePayload: Codable {
    var id: String
    var role: String
    var content: String
}

struct WorkbenchBackup: Codable {
    var tasks: [WebTaskPayload]
    var monthlyNotes: [WebMonthNotePayload]
    var diaries: [WebDiaryPayload]
    var messages: [WebMessagePayload] = []
    var diaryMessages: [WebMessagePayload] = []
    var apiKey: String? = nil
}

enum DateFormatting {
    static let dateKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let monthKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年 M月"
        return formatter
    }()

    static func minute(from value: String, fallback: Int) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return fallback }
        return min(max(parts[0] * 60 + parts[1], 0), 24 * 60 - 1)
    }
}
