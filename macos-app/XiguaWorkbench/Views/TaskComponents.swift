import SwiftUI

struct BrandCharacterImage: View {
    var body: some View {
        if
            let url = Bundle.main.url(forResource: "xigua-teacher-user-cutout", withExtension: "png"),
            let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.circle")
                .resizable()
                .scaledToFit()
                .foregroundStyle(WorkbenchTheme.green)
                .accessibilityHidden(true)
        }
    }
}

struct TaskRow: View {
    @Environment(WorkbenchStore.self) private var store
    let task: WorkbenchTask
    var showDate = false
    var edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button { store.toggleTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(task.isCompleted ? WorkbenchTheme.green : WorkbenchTheme.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "标记为未完成" : "标记为已完成")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? WorkbenchTheme.muted : WorkbenchTheme.ink)

                HStack(spacing: 8) {
                    if showDate, let date = task.date {
                        Text(date.formatted(.dateTime.month().day()))
                    }
                    if let time = task.timeRangeText { Text(time) }
                    Text(task.tag.rawValue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(WorkbenchTheme.sage, in: Capsule())
                        .overlay(Capsule().stroke(WorkbenchTheme.ink, lineWidth: 1))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WorkbenchTheme.muted)
            }

            Spacer(minLength: 4)

            Button(role: .destructive) {
                store.deleteTask(task.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WorkbenchTheme.red)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("删除任务")
            .accessibilityLabel("删除 \(task.title)")

            Menu {
                Button("编辑", action: edit)
                Button(task.date == nil ? "安排到今天" : "放入待办箱") {
                    store.moveTask(task.id, to: task.date == nil ? .now : nil)
                }
                Divider()
                Button("删除", role: .destructive) { store.deleteTask(task.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WorkbenchTheme.green)
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("编辑", action: edit)
            Button(task.isCompleted ? "标记为未完成" : "标记为已完成") { store.toggleTask(task.id) }
            Button("删除", role: .destructive) { store.deleteTask(task.id) }
        }
    }
}

struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(WorkbenchTheme.green)
            Text(title)
                .font(WorkbenchTheme.displayFont(21))
                .foregroundStyle(WorkbenchTheme.ink)
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(WorkbenchTheme.muted)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PageHeading: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        BrandPageHeading(eyebrow: eyebrow, title: title, subtitle: subtitle)
    }
}
