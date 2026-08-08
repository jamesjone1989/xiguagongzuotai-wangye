import SwiftUI

struct AgendaView: View {
    @Environment(WorkbenchStore.self) private var store
    let present: (SheetDestination) -> Void

    private var groupedTasks: [(Date, [WorkbenchTask])] {
        let grouped = Dictionary(grouping: store.upcomingTasks(from: .now)) { task in
            Calendar.current.startOfDay(for: task.date ?? .now)
        }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    PageHeading(
                        eyebrow: "AGENDA",
                        title: "接下来两周",
                        subtitle: "按时间顺序看清接下来要推进的事。"
                    )
                    Spacer()
                    Button("安排一件事") { present(.newTask(.now)) }
                        .buttonStyle(OutlineButtonStyle())
                }

                if groupedTasks.isEmpty {
                    EmptyState(
                        systemImage: "clock",
                        title: "没有即将到来的安排",
                        message: "待办箱里的事项安排日期后，会出现在这里。",
                        actionTitle: "新建任务"
                    ) { present(.newTask(.now)) }
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .hardCard(radius: 22, shadow: 8, padding: 18)
                } else {
                    VStack(spacing: 16) {
                        ForEach(groupedTasks, id: \.0) { day, tasks in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(DateFormatting.longDate.string(from: day))
                                    .font(WorkbenchTheme.displayFont(22))
                                    .foregroundStyle(WorkbenchTheme.ink)
                            ForEach(tasks) { task in
                                TaskRow(task: task) { present(.editTask(task.id)) }
                                    .softCard(radius: 11, padding: 11)
                            }
                            }
                            .hardCard(fill: Calendar.current.isDateInToday(day) ? WorkbenchTheme.sage : WorkbenchTheme.paperLight, radius: 18, shadow: 6, padding: 18)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}
