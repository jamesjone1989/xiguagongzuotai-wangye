import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case calendar
    case inbox
    case diary
    case settings
}

struct WorkbenchRootView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("今天", systemImage: "sun.max.fill") }
            .tag(AppTab.today)

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("日历", systemImage: "calendar") }
            .tag(AppTab.calendar)

            NavigationStack {
                InboxView()
            }
            .tabItem { Label("待办", systemImage: "tray.full.fill") }
            .tag(AppTab.inbox)

            NavigationStack {
                DiaryView()
            }
            .tabItem { Label("日记", systemImage: "book.closed.fill") }
            .tag(AppTab.diary)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .tint(.red)
    }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkbenchTask.updatedAt, order: .reverse) private var tasks: [WorkbenchTask]

    @State private var editorRoute: TaskEditorRoute?
    @State private var quickText = ""
    @State private var isParsing = false
    @State private var alertMessage: String?

    private var todayTasks: [WorkbenchTask] {
        tasks
            .filter { task in
                guard let date = task.scheduledAt else { return false }
                return date.isSameDay(as: .now)
            }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    private var inboxTasks: [WorkbenchTask] {
        tasks.filter { $0.scheduledAt == nil && !$0.isDone }
    }

    private var completedCount: Int {
        todayTasks.filter(\.isDone).count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                TodayHeroCard(completed: completedCount, total: todayTasks.count)

                QuickCaptureCard(
                    text: $quickText,
                    isParsing: isParsing,
                    addToInbox: addQuickTask,
                    arrangeWithAI: arrangeWithAI
                )

                DashboardSection(title: "今日日程", symbol: "clock.fill") {
                    if todayTasks.isEmpty {
                        CompactEmptyState(
                            title: "今天还没有安排",
                            message: "点击右上角的加号，给今天留下一件清楚的事。",
                            symbol: "calendar.badge.plus"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(todayTasks) { task in
                                TaskRowView(task: task, showsDate: false, onToggle: { toggle(task) })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editorRoute = TaskEditorRoute(task: task, defaultDate: nil)
                                    }
                                if task.id != todayTasks.last?.id { Divider().padding(.leading, 48) }
                            }
                        }
                    }
                }

                DashboardSection(title: "待办箱", symbol: "tray.full.fill") {
                    if inboxTasks.isEmpty {
                        CompactEmptyState(
                            title: "待办箱是空的",
                            message: "暂时不确定时间的事，可以先放在这里。",
                            symbol: "tray"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(inboxTasks.prefix(4))) { task in
                                TaskRowView(task: task, showsDate: false, onToggle: { toggle(task) })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editorRoute = TaskEditorRoute(task: task, defaultDate: nil)
                                    }
                                if task.id != inboxTasks.prefix(4).last?.id { Divider().padding(.leading, 48) }
                            }
                        }
                    }
                }

                NavigationLink {
                    WeeklyBriefView()
                } label: {
                    Label("查看本周简报", systemImage: "doc.text.image.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("今天")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = TaskEditorRoute(task: nil, defaultDate: .now)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            TaskEditorView(task: route.task, defaultDate: route.defaultDate)
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func addQuickTask() {
        let title = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        modelContext.insert(WorkbenchTask(title: title))
        try? modelContext.save()
        quickText = ""
    }

    private func arrangeWithAI() {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let apiKey = KeychainStore.loadAPIKey()
        guard !apiKey.isEmpty else {
            alertMessage = "请先到“设置”中保存 DeepSeek API Key。"
            return
        }

        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let parsed = try await DeepSeekService.parseTask(text, apiKey: apiKey)
                let scheduledAt = parsedDate(from: parsed)
                let task = WorkbenchTask(
                    title: parsed.title,
                    scheduledAt: scheduledAt,
                    durationMinutes: min(max(parsed.durationMinutes ?? 60, 15), 480),
                    tag: TaskTag(rawValue: parsed.tag ?? "") ?? .work,
                    detailText: parsed.notes ?? ""
                )
                modelContext.insert(task)
                try modelContext.save()
                quickText = ""
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? "AI 整理失败，请稍后再试。"
            }
        }
    }

    private func parsedDate(from parsed: DeepSeekService.ParsedTask) -> Date? {
        guard let dateString = parsed.date, let start = parsed.start else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(dateString) \(start)")
    }

    private func toggle(_ task: WorkbenchTask) {
        withAnimation {
            task.isDone.toggle()
            task.updatedAt = .now
            try? modelContext.save()
        }
    }
}

private struct TodayHeroCard: View {
    let completed: Int
    let total: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(axis: .horizontal)
            content(axis: .vertical)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(axis: Axis) -> some View {
        let text = VStack(alignment: .leading, spacing: 10) {
            Text(Date.now.formatted(Date.FormatStyle.chineseDay))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(total == 0 ? "先把重要的事，放回一小步。" : "今天完成了 \(completed) / \(total) 件事")
                .font(.title2.bold())
            ProgressView(value: total == 0 ? 0 : Double(completed) / Double(total))
                .tint(.red)
        }

        if axis == .horizontal {
            HStack(spacing: 18) {
                text
                Spacer(minLength: 8)
                Image("XiguaTeacher")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityHidden(true)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) { text }
        }
    }
}

private struct QuickCaptureCard: View {
    @Binding var text: String
    let isParsing: Bool
    let addToInbox: () -> Void
    let arrangeWithAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("快速记一件事", systemImage: "square.and.pencil")
                .font(.headline)

            TextField("例如：周五下午三点提交方案", text: $text, axis: .vertical)
                .lineLimit(1 ... 4)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(addToInbox)

            HStack {
                Button(action: addToInbox) {
                    Label("放入待办", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

                Spacer()

                Button(action: arrangeWithAI) {
                    if isParsing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("AI 安排", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CalendarView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case month = "月"
        case year = "年"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkbenchTask.updatedAt, order: .reverse) private var tasks: [WorkbenchTask]
    @State private var selectedDate = Date.now
    @State private var mode: DisplayMode = .month
    @State private var editorRoute: TaskEditorRoute?

    private var selectedTasks: [WorkbenchTask] {
        tasks
            .filter { $0.scheduledAt?.isSameDay(as: selectedDate) == true }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    var body: some View {
        List {
            Section {
                Picker("日历范围", selection: $mode) {
                    ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if mode == .month {
                    DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                } else {
                    YearOverview(selectedDate: $selectedDate, mode: $mode, tasks: tasks)
                }
            }

            Section("月度计划") {
                NavigationLink {
                    MonthPlanEditorView(month: selectedDate.startOfMonth)
                } label: {
                    Label(selectedDate.formatted(Date.FormatStyle.chineseMonth), systemImage: "note.text")
                }
            }

            Section(selectedDate.formatted(Date.FormatStyle.chineseDay)) {
                if selectedTasks.isEmpty {
                    Text("这一天还没有安排")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedTasks) { task in
                        TaskRowView(task: task, showsDate: false, onToggle: { toggle(task) })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorRoute = TaskEditorRoute(task: task, defaultDate: nil)
                            }
                    }
                }
            }
        }
        .navigationTitle("日历")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = TaskEditorRoute(task: nil, defaultDate: selectedDate)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            TaskEditorView(task: route.task, defaultDate: route.defaultDate)
        }
    }

    private func toggle(_ task: WorkbenchTask) {
        task.isDone.toggle()
        task.updatedAt = .now
        try? modelContext.save()
    }
}

private struct YearOverview: View {
    @Binding var selectedDate: Date
    @Binding var mode: CalendarView.DisplayMode
    let tasks: [WorkbenchTask]

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(1 ... 12, id: \.self) { month in
                Button {
                    var components = Calendar.current.dateComponents([.year], from: selectedDate)
                    components.month = month
                    components.day = 1
                    selectedDate = Calendar.current.date(from: components) ?? selectedDate
                    mode = .month
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(month)月")
                            .font(.headline)
                        Text("\(taskCount(month: month)) 项安排")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private func taskCount(month: Int) -> Int {
        let year = Calendar.current.component(.year, from: selectedDate)
        return tasks.filter { task in
            guard let date = task.scheduledAt else { return false }
            return Calendar.current.component(.year, from: date) == year &&
                Calendar.current.component(.month, from: date) == month
        }.count
    }
}

struct MonthPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [MonthlyNote]

    let month: Date
    @State private var content = ""

    private var existingNote: MonthlyNote? {
        notes.first { $0.monthStart.isSameMonth(as: month) }
    }

    var body: some View {
        Form {
            Section("这个月最重要的事") {
                TextEditor(text: $content)
                    .frame(minHeight: 180)
            }
            Section {
                Text("月度计划会保存在本机，可随时回来修改。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(month.formatted(Date.FormatStyle.chineseMonth))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { content = existingNote?.content ?? "" }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func save() {
        if let existingNote {
            existingNote.content = content
            existingNote.updatedAt = .now
        } else {
            modelContext.insert(MonthlyNote(monthStart: month, content: content))
        }
        try? modelContext.save()
        dismiss()
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkbenchTask.updatedAt, order: .reverse) private var tasks: [WorkbenchTask]
    @State private var searchText = ""
    @State private var editorRoute: TaskEditorRoute?

    private var activeTasks: [WorkbenchTask] {
        filtered.filter { $0.scheduledAt == nil && !$0.isDone }
    }

    private var completedTasks: [WorkbenchTask] {
        Array(filtered.filter(\.isDone).prefix(20))
    }

    private var filtered: [WorkbenchTask] {
        guard !searchText.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.detailText.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if activeTasks.isEmpty && completedTasks.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "没有待办" : "没有找到结果",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "暂时不确定时间的事，会留在这里。" : "试试其他关键词。")
                )
            }

            if !activeTasks.isEmpty {
                Section("待安排") {
                    ForEach(activeTasks) { task in
                        TaskRowView(task: task, showsDate: false, onToggle: { toggle(task) })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorRoute = TaskEditorRoute(task: task, defaultDate: nil)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) { delete(task) }
                                Button("安排") {
                                    editorRoute = TaskEditorRoute(task: task, defaultDate: .now)
                                }
                                .tint(.blue)
                            }
                    }
                }
            }

            if !completedTasks.isEmpty {
                Section("最近完成") {
                    ForEach(completedTasks) { task in
                        TaskRowView(task: task, showsDate: true, onToggle: { toggle(task) })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editorRoute = TaskEditorRoute(task: task, defaultDate: nil)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) { delete(task) }
                            }
                    }
                }
            }
        }
        .navigationTitle("待办")
        .searchable(text: $searchText, prompt: "搜索任务")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = TaskEditorRoute(task: nil, defaultDate: nil)
                } label: {
                    Label("新建待办", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            TaskEditorView(task: route.task, defaultDate: route.defaultDate)
        }
    }

    private func toggle(_ task: WorkbenchTask) {
        task.isDone.toggle()
        task.updatedAt = .now
        try? modelContext.save()
    }

    private func delete(_ task: WorkbenchTask) {
        withAnimation { modelContext.delete(task) }
        try? modelContext.save()
    }
}

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let task: WorkbenchTask?
    @State private var title: String
    @State private var isScheduled: Bool
    @State private var day: Date
    @State private var time: Date
    @State private var durationMinutes: Int
    @State private var tag: TaskTag
    @State private var detailText: String
    @State private var showingDeleteConfirmation = false
    @FocusState private var titleFocused: Bool

    init(task: WorkbenchTask?, defaultDate: Date?) {
        self.task = task
        let scheduled = task?.scheduledAt
        _title = State(initialValue: task?.title ?? "")
        _isScheduled = State(initialValue: scheduled != nil || defaultDate != nil)
        _day = State(initialValue: scheduled ?? defaultDate ?? .now)
        _time = State(initialValue: scheduled ?? .now)
        _durationMinutes = State(initialValue: task?.durationMinutes ?? 60)
        _tag = State(initialValue: task?.tag ?? .work)
        _detailText = State(initialValue: task?.detailText ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("要做什么？", text: $title, axis: .vertical)
                        .lineLimit(1 ... 3)
                        .focused($titleFocused)

                    Picker("分类", selection: $tag) {
                        ForEach(TaskTag.allCases) { option in
                            Label(option.rawValue, systemImage: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("安排") {
                    Toggle("加入日程", isOn: $isScheduled)
                    if isScheduled {
                        DatePicker("日期", selection: $day, displayedComponents: .date)
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                        Picker("时长", selection: $durationMinutes) {
                            ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                                Text(durationLabel(minutes)).tag(minutes)
                            }
                        }
                    }
                }

                Section("备注") {
                    TextEditor(text: $detailText)
                        .frame(minHeight: 110)
                }

                if task != nil {
                    Section {
                        Button("删除任务", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("确定删除这个任务吗？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("删除任务", role: .destructive) { deleteTask() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { if task == nil { titleFocused = true } }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduledAt = isScheduled ? Date.combining(day: day, time: time) : nil
        if let task {
            task.title = cleanTitle
            task.scheduledAt = scheduledAt
            task.durationMinutes = durationMinutes
            task.tag = tag
            task.detailText = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
            task.updatedAt = .now
        } else {
            modelContext.insert(WorkbenchTask(
                title: cleanTitle,
                scheduledAt: scheduledAt,
                durationMinutes: durationMinutes,
                tag: tag,
                detailText: detailText.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        try? modelContext.save()
        dismiss()
    }

    private func deleteTask() {
        if let task { modelContext.delete(task) }
        try? modelContext.save()
        dismiss()
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分钟" }
        if minutes == 60 { return "1 小时" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }
}

struct WeeklyBriefView: View {
    @Query(sort: \WorkbenchTask.scheduledAt) private var tasks: [WorkbenchTask]

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date.now.startOfWeek) ?? .now
    }

    private var weekTasks: [WorkbenchTask] {
        tasks.filter { task in
            guard let date = task.scheduledAt else { return false }
            return date >= Date.now.startOfWeek && date < weekEnd
        }
    }

    private var briefText: String {
        let completed = weekTasks.filter(\.isDone)
        let pending = weekTasks.filter { !$0.isDone }
        let doneLines = completed.isEmpty ? "- 暂无" : completed.map { "- \($0.title)" }.joined(separator: "\n")
        let pendingLines = pending.isEmpty ? "- 暂无" : pending.map { "- \($0.title)" }.joined(separator: "\n")
        return """
        【本周完成】
        \(doneLines)

        【仍需推进】
        \(pendingLines)
        """
    }

    var body: some View {
        List {
            Section {
                LabeledContent("本周安排", value: "\(weekTasks.count) 项")
                LabeledContent("已经完成", value: "\(weekTasks.filter(\.isDone).count) 项")
            }

            Section("本周完成") {
                if weekTasks.filter(\.isDone).isEmpty {
                    Text("暂无已完成任务").foregroundStyle(.secondary)
                } else {
                    ForEach(weekTasks.filter(\.isDone)) { task in
                        Label(task.title, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("仍需推进") {
                if weekTasks.filter({ !$0.isDone }).isEmpty {
                    Text("本周任务已经全部完成").foregroundStyle(.secondary)
                } else {
                    ForEach(weekTasks.filter { !$0.isDone }) { task in
                        Label(task.title, systemImage: "circle")
                    }
                }
            }
        }
        .navigationTitle("本周简报")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: briefText) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

struct TaskRowView: View {
    let task: WorkbenchTask
    let showsDate: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "标记为未完成" : "标记为已完成")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                HStack(spacing: 8) {
                    Label(task.tag.rawValue, systemImage: task.tag.symbol)
                    if let date = task.scheduledAt {
                        Text(showsDate ? date.formatted(date: .abbreviated, time: .shortened) : date.formatted(date: .omitted, time: .shortened))
                    } else {
                        Text("待安排")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CompactEmptyState: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    WorkbenchRootView()
        .modelContainer(for: [WorkbenchTask.self, DiaryEntry.self, MonthlyNote.self], inMemory: true)
}
