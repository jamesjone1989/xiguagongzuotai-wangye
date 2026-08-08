import SwiftUI

struct InboxView: View {
    @Environment(WorkbenchStore.self) private var store
    let present: (SheetDestination) -> Void

    private var inboxTasks: [WorkbenchTask] {
        store.tasks.filter { $0.date == nil }.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.createdAt > $1.createdAt
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    PageHeading(
                        eyebrow: "INBOX",
                        title: "待办箱",
                        subtitle: "先把事情接住，再决定什么时候做。"
                    )
                    Spacer()
                    Button("记录一件事") { present(.newTask(nil)) }
                        .buttonStyle(OutlineButtonStyle())
                }

                if inboxTasks.isEmpty {
                    EmptyState(
                        systemImage: "tray",
                        title: "待办箱是空的",
                        message: "没有日期的任务会先放在这里。",
                        actionTitle: "记录一件事"
                    ) { present(.newTask(nil)) }
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .hardCard(radius: 22, shadow: 8, padding: 18)
                } else {
                    VStack(spacing: 11) {
                        ForEach(inboxTasks) { task in
                            TaskRow(task: task) { present(.editTask(task.id)) }
                                .softCard(radius: 12, padding: 14)
                        }
                    }
                    .hardCard(radius: 22, shadow: 8, padding: 18)
                }
            }
            .padding(28)
        }
    }
}
