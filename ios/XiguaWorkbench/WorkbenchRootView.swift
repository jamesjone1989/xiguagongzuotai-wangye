import SwiftData
import SwiftUI

enum XiguaTheme {
    static let paper = Color(red: 0.969, green: 0.953, blue: 0.910)
    static let paperLight = Color(red: 1.000, green: 0.992, blue: 0.969)
    static let ink = Color(red: 0.090, green: 0.145, blue: 0.122)
    static let muted = Color(red: 0.443, green: 0.502, blue: 0.475)
    static let line = Color(red: 0.851, green: 0.831, blue: 0.780)
    static let green = Color(red: 0.184, green: 0.420, blue: 0.333)
    static let leaf = Color(red: 0.522, green: 0.678, blue: 0.455)
    static let sage = Color(red: 0.863, green: 0.918, blue: 0.875)
    static let red = Color(red: 0.941, green: 0.322, blue: 0.298)
    static let redSoft = Color(red: 0.976, green: 0.847, blue: 0.820)
    static let yellow = Color(red: 0.949, green: 0.780, blue: 0.361)
}

enum AppTab: Hashable, CaseIterable {
    case today
    case plan
    case agenda
    case brief
    case diary

    var title: String {
        switch self {
        case .today: "今天"
        case .plan: "计划"
        case .agenda: "日程"
        case .brief: "周报"
        case .diary: "日记"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .plan: "calendar"
        case .agenda: "list.bullet.rectangle"
        case .brief: "doc.text.fill"
        case .diary: "book.closed.fill"
        }
    }
}

struct WorkbenchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allTasks: [WorkbenchTask]
    @Query private var allDiaries: [DiaryEntry]
    @Query private var allNotes: [MonthlyNote]

    @State private var selectedTab: AppTab = .today
    @State private var syncController = WorkbenchSyncController()
    @State private var pendingSync: Task<Void, Never>?

    private var syncFingerprint: String {
        let tasks = allTasks
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.isDone)" }
            .sorted()
            .joined(separator: "|")
        let diaries = allDiaries
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        let notes = allNotes
            .map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970)" }
            .sorted()
            .joined(separator: "|")
        return "\(tasks)#\(diaries)#\(notes)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbol) }
                .tag(AppTab.today)

            NavigationStack { PlanView() }
                .tabItem { Label(AppTab.plan.title, systemImage: AppTab.plan.symbol) }
                .tag(AppTab.plan)

            NavigationStack { AgendaView() }
                .tabItem { Label(AppTab.agenda.title, systemImage: AppTab.agenda.symbol) }
                .tag(AppTab.agenda)

            NavigationStack { WeeklyBriefView() }
                .tabItem { Label(AppTab.brief.title, systemImage: AppTab.brief.symbol) }
                .tag(AppTab.brief)

            NavigationStack { DiaryView() }
                .tabItem { Label(AppTab.diary.title, systemImage: AppTab.diary.symbol) }
                .tag(AppTab.diary)
        }
        .tint(XiguaTheme.red)
        .toolbarBackground(XiguaTheme.paperLight, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .environment(syncController)
        .task {
            if syncController.isConfigured {
                await syncController.sync(modelContext: modelContext)
            }
        }
        .onChange(of: syncFingerprint) {
            scheduleSync()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, syncController.isConfigured {
                Task { await syncController.sync(modelContext: modelContext) }
            }
        }
        .onDisappear {
            pendingSync?.cancel()
        }
    }

    private func scheduleSync() {
        guard syncController.isConfigured else { return }
        pendingSync?.cancel()
        pendingSync = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await syncController.sync(modelContext: modelContext)
        }
    }
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            XiguaTheme.paper
            Canvas { context, size in
                for x in stride(from: 12.0, through: size.width, by: 28) {
                    for y in stride(from: 8.0, through: size.height, by: 28) {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                            with: .color(XiguaTheme.line.opacity(0.42))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct XiguaCard<Content: View>: View {
    var fill: Color = XiguaTheme.paperLight
    var border: Color = XiguaTheme.ink
    var shadow: Color = XiguaTheme.ink
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(border, lineWidth: 2)
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(shadow)
                    .offset(x: 4, y: 5)
            }
            .padding(.trailing, 4)
            .padding(.bottom, 5)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.black))
                .tracking(1.6)
                .foregroundStyle(XiguaTheme.red)
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.black))
                    .foregroundStyle(XiguaTheme.ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XiguaTheme.muted)
                }
            }
        }
    }
}

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkbenchTask.updatedAt, order: .reverse) private var tasks: [WorkbenchTask]

    @State private var editorRoute: TaskEditorRoute?
    @State private var quickText = ""
    @State private var isParsing = false
    @State private var alertMessage: String?
    @State private var showingSettings = false

    private var todayTasks: [WorkbenchTask] {
        tasks.filter { $0.scheduledAt?.isSameDay(as: .now) == true }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    private var inboxTasks: [WorkbenchTask] {
        tasks.filter { $0.scheduledAt == nil && !$0.isDone }
    }

    private var completion: Double {
        guard !todayTasks.isEmpty else { return 0 }
        return Double(todayTasks.filter(\.isDone).count) / Double(todayTasks.count)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    TodayHero(completion: completion, taskCount: todayTasks.count)

                    QuickCaptureCard(
                        text: $quickText,
                        isParsing: isParsing,
                        addToInbox: addQuickTask,
                        arrangeWithAI: arrangeWithAI
                    )

                    SectionHeading(
                        eyebrow: "TODAY / TIMELINE",
                        title: "今天的时间线",
                        detail: todayTasks.isEmpty ? "留白也很好" : "\(todayTasks.count) 件事"
                    )

                    XiguaCard {
                        DayTimeline(
                            tasks: todayTasks,
                            onOpen: { editorRoute = TaskEditorRoute(task: $0, defaultDate: nil) },
                            onToggle: toggle,
                            onReschedule: reschedule
                        )
                    }

                    SectionHeading(
                        eyebrow: "INBOX / LATER",
                        title: "先放在待办箱",
                        detail: "\(inboxTasks.count) 件待安排"
                    )

                    XiguaCard(fill: XiguaTheme.sage) {
                        if inboxTasks.isEmpty {
                            EmptyNote(
                                symbol: "tray",
                                title: "待办箱空空的",
                                message: "暂时不确定时间的事，可以先放在这里。"
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(inboxTasks.prefix(6))) { task in
                                    InboxTaskRow(
                                        task: task,
                                        onOpen: { editorRoute = TaskEditorRoute(task: task, defaultDate: nil) },
                                        onSchedule: { scheduleToday(task) },
                                        onToggle: { toggle(task) }
                                    )
                                    if task.id != inboxTasks.prefix(6).last?.id {
                                        Divider().overlay(XiguaTheme.ink.opacity(0.18))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("我的工作台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("设置")
            }
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
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
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
            alertMessage = "请先在设置中保存 DeepSeek API Key。"
            return
        }

        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let parsed = try await DeepSeekService.parseTask(text, apiKey: apiKey)
                let task = WorkbenchTask(
                    title: parsed.title,
                    scheduledAt: parsedDate(from: parsed),
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
        withAnimation(.snappy) {
            task.isDone.toggle()
            task.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func scheduleToday(_ task: WorkbenchTask) {
        let calendar = Calendar.current
        let occupiedHours = Set(todayTasks.compactMap { task in
            task.scheduledAt.map { calendar.component(.hour, from: $0) }
        })
        let hour = (9 ... 20).first { !occupiedHours.contains($0) } ?? 9
        task.scheduledAt = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)
        task.updatedAt = .now
        try? modelContext.save()
    }

    private func reschedule(_ task: WorkbenchTask, minutes: Int) {
        guard let date = task.scheduledAt else { return }
        let day = date.startOfDay
        task.scheduledAt = Calendar.current.date(byAdding: .minute, value: max(8 * 60, min(21 * 60 + 45, minutes)), to: day)
        task.updatedAt = .now
        try? modelContext.save()
    }
}

private struct TodayHero: View {
    let completion: Double
    let taskCount: Int

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5 ..< 12: "早上好"
        case 12 ..< 18: "下午好"
        default: "晚上好"
        }
    }

    var body: some View {
        XiguaCard(fill: XiguaTheme.yellow) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Date.now.formatted(Date.FormatStyle.chineseDay))
                        .font(.caption.weight(.black))
                        .foregroundStyle(XiguaTheme.green)
                    Text("\(greeting)，\n今天要做什么？")
                        .font(.system(.title, design: .rounded, weight: .black))
                        .foregroundStyle(XiguaTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if taskCount > 0 {
                        ProgressView(value: completion)
                            .tint(XiguaTheme.green)
                            .background(XiguaTheme.paperLight.opacity(0.55), in: Capsule())
                        Text("已经完成 \(Int(completion * Double(taskCount))) / \(taskCount) 件")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XiguaTheme.ink.opacity(0.72))
                    } else {
                        Text("先写下一件最重要的小事。")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(XiguaTheme.ink.opacity(0.72))
                    }
                }
                Spacer(minLength: 0)
                Image("XiguaTeacher")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 130, alignment: .bottom)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct QuickCaptureCard: View {
    @Binding var text: String
    let isParsing: Bool
    let addToInbox: () -> Void
    let arrangeWithAI: () -> Void

    var body: some View {
        XiguaCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("随手记下来", systemImage: "pencil.line")
                    .font(.headline.weight(.black))
                    .foregroundStyle(XiguaTheme.ink)
                TextField("例如：明天下午 3 点交方案，预计 1 小时", text: $text, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .padding(12)
                    .background(XiguaTheme.paper, in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13).stroke(XiguaTheme.ink, lineWidth: 1.5)
                    }
                    .submitLabel(.done)
                    .onSubmit(addToInbox)

                HStack(spacing: 10) {
                    Button(action: addToInbox) {
                        Label("放入待办箱", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(XiguaOutlineButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(action: arrangeWithAI) {
                        if isParsing {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Label("AI 安排", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(XiguaFilledButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                }
            }
        }
    }
}

struct XiguaFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(XiguaTheme.green.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(XiguaTheme.ink, lineWidth: 1.5) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct XiguaOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(XiguaTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(XiguaTheme.paperLight.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(XiguaTheme.ink, lineWidth: 1.5) }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct DayTimeline: View {
    private let startHour = 8
    private let endHour = 22
    private let hourHeight: CGFloat = 66

    let tasks: [WorkbenchTask]
    let onOpen: (WorkbenchTask) -> Void
    let onToggle: (WorkbenchTask) -> Void
    let onReschedule: (WorkbenchTask, Int) -> Void

    private var visibleTasks: [WorkbenchTask] {
        tasks.filter { task in
            guard let date = task.scheduledAt else { return false }
            let hour = Calendar.current.component(.hour, from: date)
            return hour >= startHour && hour < endHour
        }
    }

    var body: some View {
        if visibleTasks.isEmpty {
            EmptyNote(
                symbol: "clock",
                title: "今天还没有安排",
                message: "时间线从 8:00 到 22:00。把待办放进来，给一天留出节奏。"
            )
            .frame(minHeight: 150)
        } else {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(startHour ..< endHour, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%02d:00", hour))
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(XiguaTheme.muted)
                                .frame(width: 42, alignment: .leading)
                            Rectangle()
                                .fill(XiguaTheme.line)
                                .frame(height: 1)
                                .padding(.top, 7)
                        }
                        .frame(height: hourHeight, alignment: .top)
                    }
                }

                ForEach(visibleTasks) { task in
                    TimelineTaskBlock(
                        task: task,
                        hourHeight: hourHeight,
                        startHour: startHour,
                        onOpen: { onOpen(task) },
                        onToggle: { onToggle(task) },
                        onMove: { deltaMinutes in
                            let calendar = Calendar.current
                            guard let scheduled = task.scheduledAt else { return }
                            let original = calendar.component(.hour, from: scheduled) * 60 + calendar.component(.minute, from: scheduled)
                            onReschedule(task, original + deltaMinutes)
                        }
                    )
                }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight)
        }
    }
}

private struct TimelineTaskBlock: View {
    let task: WorkbenchTask
    let hourHeight: CGFloat
    let startHour: Int
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onMove: (Int) -> Void

    @State private var dragOffset: CGFloat = 0

    private var yOffset: CGFloat {
        guard let date = task.scheduledAt else { return 0 }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double((components.hour ?? startHour) * 60 + (components.minute ?? 0) - startHour * 60)
        return CGFloat(minutes / 60) * hourHeight
    }

    private var height: CGFloat {
        max(48, CGFloat(task.durationMinutes) / 60 * hourHeight - 4)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.headline)
                    .foregroundStyle(task.isDone ? XiguaTheme.green : XiguaTheme.ink)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.bold))
                    .strikethrough(task.isDone)
                    .lineLimit(height < 62 ? 1 : 2)
                if height >= 62, let date = task.scheduledAt {
                    Text("\(date.formatted(date: .omitted, time: .shortened)) · \(task.durationMinutes) 分钟")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(XiguaTheme.ink.opacity(0.65))
                }
            }
            Spacer(minLength: 2)
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.bold))
                .foregroundStyle(XiguaTheme.ink.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(taskColor, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(XiguaTheme.ink, lineWidth: 1.5) }
        .offset(x: 52, y: yOffset + dragOffset)
        .padding(.trailing, 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    let rawMinutes = Int((value.translation.height / hourHeight * 60).rounded())
                    let snapped = Int((Double(rawMinutes) / 15).rounded()) * 15
                    dragOffset = 0
                    if snapped != 0 { onMove(snapped) }
                }
        )
        .accessibilityLabel("\(task.title)，可上下拖动调整时间")
    }

    private var taskColor: Color {
        switch task.tag {
        case .work: XiguaTheme.sage
        case .life: XiguaTheme.yellow.opacity(0.72)
        case .important: XiguaTheme.redSoft
        }
    }
}

private struct InboxTaskRow: View {
    let task: WorkbenchTask
    let onOpen: () -> Void
    let onSchedule: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? XiguaTheme.green : XiguaTheme.ink)
            }
            .buttonStyle(.plain)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.body.weight(.bold))
                        .foregroundStyle(XiguaTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(task.tag.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(XiguaTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onSchedule) {
                Image(systemName: "calendar.badge.plus")
                    .frame(width: 44, height: 44)
                    .background(XiguaTheme.paperLight, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("安排到今天")
        }
        .padding(.vertical, 7)
    }
}

private struct EmptyNote: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(XiguaTheme.green)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline.weight(.black)).foregroundStyle(XiguaTheme.ink)
                Text(message).font(.subheadline).foregroundStyle(XiguaTheme.muted)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

enum PlanScope: String, CaseIterable, Identifiable {
    case year = "年"
    case month = "月"
    var id: String { rawValue }
}

private struct MonthNoteRoute: Identifiable {
    let month: Date
    var id: TimeInterval { month.timeIntervalSinceReferenceDate }
}

struct PlanView: View {
    @Query(sort: \WorkbenchTask.scheduledAt) private var tasks: [WorkbenchTask]
    @State private var scope: PlanScope = .month
    @State private var focusMonth = Date.now.startOfMonth
    @State private var selectedDay = Date.now.startOfDay
    @State private var editorRoute: TaskEditorRoute?
    @State private var noteRoute: MonthNoteRoute?

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Picker("计划范围", selection: $scope) {
                        ForEach(PlanScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("切换年计划或月计划")

                    if scope == .year {
                        YearOverview(tasks: tasks, year: focusMonth, onSelect: { month in
                            focusMonth = month
                            selectedDay = month
                            scope = .month
                        })
                    } else {
                        MonthOverview(
                            tasks: tasks,
                            month: $focusMonth,
                            selectedDay: $selectedDay,
                            onEditNote: { noteRoute = MonthNoteRoute(month: focusMonth) },
                            onOpenTask: { editorRoute = TaskEditorRoute(task: $0, defaultDate: nil) }
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editorRoute = TaskEditorRoute(task: nil, defaultDate: selectedDay) } label: {
                    Label("添加任务", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            TaskEditorView(task: route.task, defaultDate: route.defaultDate)
        }
        .sheet(item: $noteRoute) { route in
            MonthPlanEditorView(month: route.month)
        }
    }
}

private struct YearOverview: View {
    let tasks: [WorkbenchTask]
    let year: Date
    let onSelect: (Date) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(
                eyebrow: "YEAR / OVERVIEW",
                title: "\(Calendar.current.component(.year, from: year)) 年",
                detail: "十二个月，一眼看完"
            )
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1 ... 12, id: \.self) { month in
                    let date = monthDate(month)
                    Button { onSelect(date) } label: {
                        MiniMonthCard(month: date, tasks: tasks.filter { $0.scheduledAt?.isSameMonth(as: date) == true })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func monthDate(_ month: Int) -> Date {
        var components = Calendar.current.dateComponents([.year], from: year)
        components.month = month
        components.day = 1
        return Calendar.current.date(from: components) ?? year
    }
}

private struct MiniMonthCard: View {
    let month: Date
    let tasks: [WorkbenchTask]

    var body: some View {
        XiguaCard(fill: month.isSameMonth(as: .now) ? XiguaTheme.yellow : XiguaTheme.paperLight, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Calendar.current.component(.month, from: month)) 月")
                        .font(.title3.weight(.black))
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.caption.monospacedDigit().weight(.black))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(XiguaTheme.redSoft, in: Capsule())
                }
                HStack(spacing: 4) {
                    ForEach(0 ..< 5, id: \.self) { index in
                        Capsule()
                            .fill(index < min(tasks.count, 5) ? XiguaTheme.green : XiguaTheme.line)
                            .frame(height: 5)
                    }
                }
                Text(tasks.first?.title ?? "给这个月留一句话")
                    .font(.caption)
                    .foregroundStyle(XiguaTheme.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            }
        }
    }
}

private struct MonthOverview: View {
    let tasks: [WorkbenchTask]
    @Binding var month: Date
    @Binding var selectedDay: Date
    let onEditNote: () -> Void
    let onOpenTask: (WorkbenchTask) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    private var cells: [Date?] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1 ..< 2
        let weekday = calendar.component(.weekday, from: month)
        let mondayOffset = (weekday + 5) % 7
        var result = Array<Date?>(repeating: nil, count: mondayOffset)
        result += range.compactMap { day in calendar.date(byAdding: .day, value: day - 1, to: month) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private var dayTasks: [WorkbenchTask] {
        tasks.filter { $0.scheduledAt?.isSameDay(as: selectedDay) == true }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            XiguaCard {
                VStack(spacing: 14) {
                    HStack {
                        Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        Spacer()
                        VStack(spacing: 2) {
                            Text(month.formatted(Date.FormatStyle.chineseMonth)).font(.title3.weight(.black))
                            Button("月度便签", action: onEditNote).font(.caption.weight(.bold)).foregroundStyle(XiguaTheme.green)
                        }
                        Spacer()
                        Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    }
                    .foregroundStyle(XiguaTheme.ink)

                    LazyVGrid(columns: columns, spacing: 7) {
                        ForEach(weekdays, id: \.self) { Text($0).font(.caption2.weight(.black)).foregroundStyle(XiguaTheme.muted) }
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                            if let day {
                                DayCell(
                                    day: day,
                                    isSelected: day.isSameDay(as: selectedDay),
                                    isToday: day.isSameDay(as: .now),
                                    taskCount: tasks.filter { $0.scheduledAt?.isSameDay(as: day) == true }.count,
                                    action: { selectedDay = day }
                                )
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                }
            }

            SectionHeading(
                eyebrow: "DAY / NOTES",
                title: selectedDay.formatted(.dateTime.month(.wide).day()),
                detail: dayTasks.isEmpty ? "没有安排" : "\(dayTasks.count) 件事"
            )
            XiguaCard(fill: XiguaTheme.sage) {
                if dayTasks.isEmpty {
                    EmptyNote(symbol: "calendar", title: "这一天是空的", message: "点右上角的加号，为这一天安排一件事。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(dayTasks) { task in
                            Button { onOpenTask(task) } label: {
                                TaskRowView(task: task, showsDate: false, onToggle: {})
                            }
                            .buttonStyle(.plain)
                            if task.id != dayTasks.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func moveMonth(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month)?.startOfMonth ?? month
        selectedDay = month
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let taskCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.subheadline.monospacedDigit().weight(isToday ? .black : .semibold))
                HStack(spacing: 2) {
                    ForEach(0 ..< min(taskCount, 3), id: \.self) { _ in
                        Circle().fill(isSelected ? .white : XiguaTheme.red).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .foregroundStyle(isSelected ? .white : XiguaTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? XiguaTheme.green : (isToday ? XiguaTheme.yellow.opacity(0.7) : .clear), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

struct MonthPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [MonthlyNote]
    let month: Date
    @State private var content = ""

    private var note: MonthlyNote? { notes.first { $0.monthStart.isSameMonth(as: month) } }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(alignment: .leading, spacing: 16) {
                    Text("这个月，我想记住……")
                        .font(.title2.weight(.black))
                        .foregroundStyle(XiguaTheme.ink)
                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(XiguaTheme.yellow.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(XiguaTheme.ink, lineWidth: 2) }
                }
                .padding()
            }
            .navigationTitle(month.formatted(Date.FormatStyle.chineseMonth))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.bold) }
            }
            .onAppear { content = note?.content ?? "" }
        }
    }

    private func save() {
        if let note {
            note.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            note.updatedAt = .now
        } else {
            modelContext.insert(MonthlyNote(monthStart: month, content: content.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        try? modelContext.save()
        dismiss()
    }
}

struct AgendaView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkbenchTask.scheduledAt) private var tasks: [WorkbenchTask]
    @State private var selectedDay = Date.now.startOfDay
    @State private var editorRoute: TaskEditorRoute?

    private var dates: [Date] {
        (-2 ... 8).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: .now.startOfDay) }
    }

    private var dayTasks: [WorkbenchTask] {
        tasks.filter { $0.scheduledAt?.isSameDay(as: selectedDay) == true }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(dates, id: \.self) { date in
                                DatePill(date: date, isSelected: date.isSameDay(as: selectedDay)) {
                                    selectedDay = date
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    SectionHeading(
                        eyebrow: "AGENDA / DAY",
                        title: selectedDay.isSameDay(as: .now) ? "今天" : selectedDay.formatted(.dateTime.month(.wide).day()),
                        detail: "\(dayTasks.count) 件事"
                    )

                    XiguaCard {
                        DayTimeline(
                            tasks: dayTasks,
                            onOpen: { editorRoute = TaskEditorRoute(task: $0, defaultDate: nil) },
                            onToggle: toggle,
                            onReschedule: reschedule
                        )
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("日程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editorRoute = TaskEditorRoute(task: nil, defaultDate: selectedDay) } label: {
                    Label("添加任务", systemImage: "plus")
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

    private func reschedule(_ task: WorkbenchTask, minutes: Int) {
        task.scheduledAt = Calendar.current.date(byAdding: .minute, value: max(8 * 60, min(21 * 60 + 45, minutes)), to: selectedDay.startOfDay)
        task.updatedAt = .now
        try? modelContext.save()
    }
}

private struct DatePill: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.black))
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.title3.monospacedDigit().weight(.black))
            }
            .foregroundStyle(isSelected ? .white : XiguaTheme.ink)
            .frame(width: 54, height: 62)
            .background(isSelected ? XiguaTheme.green : XiguaTheme.paperLight, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(XiguaTheme.ink, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
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
        _time = State(initialValue: scheduled ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now)
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
                Section("备注") { TextEditor(text: $detailText).frame(minHeight: 110) }
                if task != nil {
                    Section { Button("删除任务", role: .destructive) { showingDeleteConfirmation = true } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(XiguaTheme.paper)
            .navigationTitle(task == nil ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("确定删除这个任务吗？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("删除任务", role: .destructive, action: deleteTask)
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

    private var completed: [WorkbenchTask] { weekTasks.filter(\.isDone) }
    private var pending: [WorkbenchTask] { weekTasks.filter { !$0.isDone } }
    private var rate: Double { weekTasks.isEmpty ? 0 : Double(completed.count) / Double(weekTasks.count) }

    private var briefText: String {
        let doneLines = completed.isEmpty ? "- 暂无" : completed.map { "- \($0.title)" }.joined(separator: "\n")
        let pendingLines = pending.isEmpty ? "- 暂无" : pending.map { "- \($0.title)" }.joined(separator: "\n")
        return "【本周完成】\n\(doneLines)\n\n【仍需推进】\n\(pendingLines)"
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    XiguaCard(fill: XiguaTheme.yellow) {
                        HStack(spacing: 18) {
                            ZStack {
                                Circle().stroke(XiguaTheme.paperLight.opacity(0.65), lineWidth: 12)
                                Circle()
                                    .trim(from: 0, to: rate)
                                    .stroke(XiguaTheme.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(Int(rate * 100))%")
                                    .font(.title3.monospacedDigit().weight(.black))
                            }
                            .frame(width: 92, height: 92)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("本周进度")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(XiguaTheme.green)
                                Text(completed.isEmpty ? "先完成一件\n最重要的事" : "已经完成\n\(completed.count) 件事")
                                    .font(.title2.weight(.black))
                                    .foregroundStyle(XiguaTheme.ink)
                            }
                            Spacer()
                        }
                    }

                    BriefTaskSection(title: "本周完成", eyebrow: "DONE", tasks: completed, empty: "完成的任务会在这里留下痕迹。", color: XiguaTheme.sage)
                    BriefTaskSection(title: "仍需推进", eyebrow: "NEXT", tasks: pending, empty: "本周任务已经全部完成。", color: XiguaTheme.redSoft)

                    XiguaCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("给这一周一句话")
                                .font(.headline.weight(.black))
                            Text(weekTasks.isEmpty ? "这一周还没有安排。先从下一件清楚的小事开始。" : "做过的事值得被看见，没做完的事也只是下一步。")
                                .font(.body)
                                .foregroundStyle(XiguaTheme.muted)
                            ShareLink(item: briefText) {
                                Label("分享本周简报", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(XiguaOutlineButtonStyle())
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("本周简报")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BriefTaskSection: View {
    let title: String
    let eyebrow: String
    let tasks: [WorkbenchTask]
    let empty: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(eyebrow: eyebrow, title: title, detail: "\(tasks.count) 件")
            XiguaCard(fill: color) {
                if tasks.isEmpty {
                    Text(empty).font(.subheadline).foregroundStyle(XiguaTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tasks) { task in
                            Label(task.title, systemImage: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(XiguaTheme.ink)
                        }
                    }
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
                    .foregroundStyle(task.isDone ? XiguaTheme.green : XiguaTheme.ink)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? XiguaTheme.muted : XiguaTheme.ink)
                HStack(spacing: 8) {
                    Label(task.tag.rawValue, systemImage: task.tag.symbol)
                    if let date = task.scheduledAt {
                        Text(showsDate ? date.formatted(date: .abbreviated, time: .shortened) : date.formatted(date: .omitted, time: .shortened))
                    } else {
                        Text("待安排")
                    }
                }
                .font(.caption)
                .foregroundStyle(XiguaTheme.muted)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(XiguaTheme.muted)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

#Preview {
    WorkbenchRootView()
        .modelContainer(for: [WorkbenchTask.self, DiaryEntry.self, MonthlyNote.self], inMemory: true)
}
