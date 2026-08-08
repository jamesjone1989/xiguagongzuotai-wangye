import SwiftUI

struct TodayView: View {
    @Environment(WorkbenchStore.self) private var store
    @Binding var selectedDate: Date
    let present: (SheetDestination) -> Void
    @State private var quickTitle = ""
    @State private var isExtracting = false
    @State private var isTimelineTargeted = false
    @State private var isInboxTargeted = false
    @FocusState private var quickFieldFocused: Bool

    private let timelineStart = 8 * 60
    private let timelineEnd = 20 * 60
    private let hourHeight: CGFloat = 46

    private var tasks: [WorkbenchTask] { store.tasks(on: selectedDate) }
    private var inboxTasks: [WorkbenchTask] {
        store.tasks
            .filter { $0.date == nil && !$0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var completedCount: Int { tasks.filter(\.isCompleted).count }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        scheduleCard
                            .frame(minWidth: 520)
                        inboxCard
                            .frame(width: 290)
                    }
                    VStack(spacing: 24) {
                        scheduleCard
                        inboxCard
                    }
                }
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dateEyebrow)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(WorkbenchTheme.green)
                    Text("这一天要做什么？")
                        .font(WorkbenchTheme.displayFont(45))
                        .tracking(-1.8)
                        .foregroundStyle(WorkbenchTheme.ink)
                    Text("直接写下来：有具体时间就安排到日程，没有时间就放进待办箱。")
                        .font(.system(size: 14))
                        .foregroundStyle(WorkbenchTheme.muted)
                }

                Spacer(minLength: 12)
                dateControls
            }

            HStack(alignment: .bottom, spacing: 16) {
                TextField("例如：上午十点开项目会；整理培训资料；给妈妈回电话", text: $quickTitle, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(2...3)
                    .textFieldStyle(.plain)
                    .focused($quickFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                    .background(WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(WorkbenchTheme.ink, lineWidth: 2))
                    .onSubmit { Task { await extractTasks() } }

                Button {
                    Task { await extractTasks() }
                } label: {
                    HStack(spacing: 7) {
                        if isExtracting { ProgressView().controlSize(.small) }
                        Text(isExtracting ? "正在整理" : "帮我安排")
                    }
                }
                    .buttonStyle(SolidButtonStyle(fill: WorkbenchTheme.green))
                    .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExtracting)
                    .opacity(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExtracting ? 0.58 : 1)

                BrandCharacterImage()
                    .frame(width: 108, height: 104)
                    .offset(y: 8)
            }
        }
        .hardCard(fill: WorkbenchTheme.sage, radius: 22, shadow: 9, padding: 24)
    }

    private var dateControls: some View {
        HStack(spacing: 8) {
            Button { moveDay(-1) } label: { Image(systemName: "arrow.left") }
                .buttonStyle(SquareBrandButtonStyle())
                .help("前一天")

            Text(selectedDate.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(WorkbenchTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(WorkbenchTheme.ink, lineWidth: 2))

            Button { moveDay(1) } label: { Image(systemName: "arrow.right") }
                .buttonStyle(SquareBrandButtonStyle())
                .help("后一天")

            Button("今天") { selectedDate = .now }
                .buttonStyle(OutlineButtonStyle())
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("从早到晚")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(WorkbenchTheme.green)
                    Text("当日日程")
                        .font(WorkbenchTheme.displayFont(28))
                        .foregroundStyle(WorkbenchTheme.ink)
                    Text("\(tasks.count) 项安排 · \(completedCount) 项已完成")
                        .font(.system(size: 12))
                        .foregroundStyle(WorkbenchTheme.muted)
                }
                Spacer()
                Button("安排一件事") { present(.newTask(selectedDate)) }
                    .buttonStyle(OutlineButtonStyle())
            }

            timeline
        }
        .hardCard(radius: 22, shadow: 9, padding: 22)
    }

    private var timeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(8...20, id: \.self) { hour in
                    let y = CGFloat(hour - 8) * hourHeight
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.muted)
                        .frame(width: 54, alignment: .trailing)
                        .position(x: 27, y: y + 8)
                    Path { path in
                        path.move(to: CGPoint(x: 68, y: y + 8))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y + 8))
                    }
                    .stroke(WorkbenchTheme.line, lineWidth: 1)
                }

                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    timelineTask(task, index: index, totalWidth: proxy.size.width)
                }
            }
            .background(isTimelineTargeted ? WorkbenchTheme.yellow.opacity(0.18) : Color.clear)
            .overlay {
                if isTimelineTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(WorkbenchTheme.yellow, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                }
            }
            .dropDestination(for: String.self) { items, location in
                guard let value = items.first, let id = UUID(uuidString: value) else { return false }
                let rawMinute = timelineStart + Int(max(location.y - 8, 0) / hourHeight * 60)
                store.scheduleTask(id, on: selectedDate, startMinute: rawMinute)
                return true
            } isTargeted: { isTimelineTargeted = $0 }
        }
        .frame(height: CGFloat((timelineEnd - timelineStart) / 60) * hourHeight + 20)
    }

    private func timelineTask(_ task: WorkbenchTask, index: Int, totalWidth: CGFloat) -> some View {
        let clampedStart = min(max(task.startMinute, timelineStart), timelineEnd - 15)
        let clampedEnd = min(max(task.endMinute, clampedStart + 15), timelineEnd)
        let y = CGFloat(clampedStart - timelineStart) / 60 * hourHeight + 12
        let height = max(CGFloat(clampedEnd - clampedStart) / 60 * hourHeight - 4, 34)
        let available = max(totalWidth - 80, 220)
        let useTwoLanes = tasksOverlap(at: index)
        let width = useTwoLanes ? (available - 8) / 2 : available
        let lane = useTwoLanes ? index % 2 : 0
        let x = 74 + CGFloat(lane) * (width + 8)

        return HStack(spacing: 8) {
            Button { store.toggleTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.isCompleted ? WorkbenchTheme.green : WorkbenchTheme.ink)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 13, weight: .bold))
                .strikethrough(task.isCompleted)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(task.tag.rawValue)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(WorkbenchTheme.green)
            Button(role: .destructive) { store.deleteTask(task.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WorkbenchTheme.red)
            }
            .buttonStyle(.plain)
            .help("删除任务")
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: height, alignment: .leading)
        .background(task.isCompleted ? WorkbenchTheme.sage.opacity(0.55) : WorkbenchTheme.sage)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchTheme.ink, lineWidth: 1.7))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) { present(.editTask(task.id)) }
        .draggable(task.id.uuidString)
        .position(x: x + width / 2, y: y + height / 2)
    }

    private var inboxCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("没有具体时间")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(WorkbenchTheme.green)
                    Text("待办箱 · \(inboxTasks.count)")
                        .font(WorkbenchTheme.displayFont(27))
                        .foregroundStyle(WorkbenchTheme.ink)
                }
                Spacer()
                Button("添加 +") { present(.newTask(nil)) }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WorkbenchTheme.yellow)
            }

            Text("先把事情接住，再拖到具体日期去安排。")
                .font(.system(size: 12))
                .foregroundStyle(WorkbenchTheme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchTheme.sage)

            if inboxTasks.isEmpty {
                EmptyState(
                    systemImage: "tray",
                    title: "待办箱是空的",
                    message: "没有时间的事情可以先放在这里。",
                    actionTitle: "记录一件事"
                ) { present(.newTask(nil)) }
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 10) {
                    ForEach(inboxTasks.prefix(7)) { task in
                        TaskRow(task: task) { present(.editTask(task.id)) }
                            .softCard(radius: 12, padding: 12)
                            .draggable(task.id.uuidString)
                    }
                }
            }
            Spacer(minLength: 8)
        }
        .hardCard(radius: 22, shadow: 9, padding: 20)
        .overlay {
            if isInboxTargeted {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(WorkbenchTheme.yellow, style: StrokeStyle(lineWidth: 4, dash: [9, 6]))
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value) else { return false }
            store.moveTask(id, to: nil)
            return true
        } isTargeted: { isInboxTargeted = $0 }
    }

    private var dateEyebrow: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日EEEE"
        return formatter.string(from: selectedDate)
    }

    private func tasksOverlap(at index: Int) -> Bool {
        guard tasks.indices.contains(index) else { return false }
        let task = tasks[index]
        return tasks.enumerated().contains { otherIndex, other in
            otherIndex != index && task.startMinute < other.endMinute && other.startMinute < task.endMinute
        }
    }

    private func moveDay(_ amount: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: amount, to: selectedDate) ?? selectedDate
    }

    @MainActor
    private func extractTasks() async {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let apiKey = KeychainStore.readDeepSeekKey()
        guard !apiKey.isEmpty else {
            store.addQuickTask(title: title, date: nil)
            quickTitle = ""
            store.notice = "未配置 DeepSeek，已先放入待办箱；可在设置中填写 API Key。"
            return
        }

        isExtracting = true
        defer { isExtracting = false }
        do {
            let extracted = try await DeepSeekService.shared.extractTasks(
                from: title,
                selectedDate: selectedDate,
                apiKey: apiKey
            )
            let tasks = extracted.map(\.workbenchTask)
            guard !tasks.isEmpty else { throw DeepSeekError.emptyResponse }
            let inboxCount = tasks.filter { $0.date == nil }.count
            store.addTasks(
                tasks,
                message: inboxCount > 0
                    ? "已整理 \(tasks.count) 项，\(inboxCount) 项先进入待办箱"
                    : "已把 \(tasks.count) 项安排到日程"
            )
            quickTitle = ""
            quickFieldFocused = true
        } catch {
            store.notice = error.localizedDescription
        }
    }
}
