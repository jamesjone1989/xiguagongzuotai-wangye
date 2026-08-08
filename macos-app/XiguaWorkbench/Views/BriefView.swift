import SwiftUI

struct BriefView: View {
    @Environment(WorkbenchStore.self) private var store

    private var weekInterval: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)
    }

    private var weekTasks: [WorkbenchTask] {
        guard let weekInterval else { return [] }
        return store.tasks.filter { task in
            guard let date = task.date else { return false }
            return weekInterval.contains(date)
        }
    }

    private var completed: [WorkbenchTask] { weekTasks.filter(\.isCompleted) }
    private var pending: [WorkbenchTask] { weekTasks.filter { !$0.isCompleted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(
                    eyebrow: "WEEKLY BRIEF",
                    title: "本周简报",
                    subtitle: "用真实完成的事情，回看这一周。"
                )

                HStack(spacing: 14) {
                    metric(title: "本周任务", value: weekTasks.count, systemImage: "list.bullet", fill: WorkbenchTheme.yellow)
                    metric(title: "已完成", value: completed.count, systemImage: "checkmark.circle", fill: WorkbenchTheme.sage)
                    metric(title: "待推进", value: pending.count, systemImage: "arrow.forward.circle", fill: WorkbenchTheme.redSoft)
                    metric(title: "日记", value: recentDiaries.count, systemImage: "book.closed", fill: WorkbenchTheme.paperLight)
                }

                briefSection(title: "这一周完成了什么", tasks: completed, empty: "这一周还没有标记完成的任务。")
                briefSection(title: "接下来要继续推进", tasks: pending, empty: "本周没有遗留任务。")

                VStack(alignment: .leading, spacing: 12) {
                    Label("留给自己的问题", systemImage: "quote.bubble")
                        .font(.title3.weight(.semibold))
                    Text("这一周，哪一件事最值得继续？哪一件事其实可以放下？")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .workbenchPanel()
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var recentDiaries: [DiaryEntry] {
        guard let weekInterval else { return [] }
        return store.diaryEntries.filter { weekInterval.contains($0.date) }
    }

    private func metric(title: String, value: Int, systemImage: String, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.workbenchGreen)
                .font(.title2)
            Text("\(value)").font(WorkbenchTheme.displayFont(34))
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: fill, radius: 15, padding: 16)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(WorkbenchTheme.ink)
                .offset(x: 4, y: 4)
        }
    }

    private func briefSection(title: String, tasks: [WorkbenchTask], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            if tasks.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.workbenchGreen)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(.body.weight(.medium))
                            if !task.notes.isEmpty {
                                Text(task.notes).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .hardCard(radius: 18, shadow: 6, padding: 18)
    }
}
