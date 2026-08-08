import SwiftUI

struct TaskEditorView: View {
    @Environment(WorkbenchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkbenchTask
    @State private var isScheduled: Bool
    @State private var scheduledAt: Date
    @State private var duration: Int
    @FocusState private var titleFocused: Bool

    init(task: WorkbenchTask?, suggestedDate: Date?) {
        let value = task ?? WorkbenchTask(date: suggestedDate)
        _draft = State(initialValue: value)
        _isScheduled = State(initialValue: value.date != nil)
        let day = value.date ?? suggestedDate ?? .now
        let time = Calendar.current.date(bySettingHour: value.startMinute / 60, minute: value.startMinute % 60, second: 0, of: day) ?? day
        _scheduledAt = State(initialValue: time)
        _duration = State(initialValue: max(value.endMinute - value.startMinute, 15))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务") {
                    TextField("要完成什么？", text: $draft.title)
                        .font(.title3)
                        .focused($titleFocused)

                    Picker("分类", selection: $draft.tag) {
                        ForEach(TaskTag.allCases) { tag in
                            Label(tag.rawValue, systemImage: tag.systemImage).tag(tag)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("安排") {
                    Toggle("放入日程", isOn: $isScheduled)
                    if isScheduled {
                        DatePicker("日期与时间", selection: $scheduledAt)
                        Stepper("时长：\(duration) 分钟", value: $duration, in: 15...480, step: 15)
                    } else {
                        LabeledContent("位置", value: "待办箱")
                    }
                }

                Section("备注") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 92)
                        .accessibilityLabel("任务备注")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(store.task(id: draft.id) == nil ? "新建任务" : "编辑任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 520, height: 500)
        .onAppear { titleFocused = true }
    }

    private func save() {
        if isScheduled {
            draft.date = Calendar.current.startOfDay(for: scheduledAt)
            let components = Calendar.current.dateComponents([.hour, .minute], from: scheduledAt)
            draft.startMinute = (components.hour ?? 9) * 60 + (components.minute ?? 0)
            draft.endMinute = min(draft.startMinute + duration, 24 * 60)
        } else {
            draft.date = nil
        }
        store.upsert(draft)
        dismiss()
    }
}

struct DiaryEditorView: View {
    @Environment(WorkbenchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DiaryEntry
    @FocusState private var bodyFocused: Bool

    private let moods = ["平静", "开心", "充实", "疲惫", "焦虑", "难过"]

    init(diary: DiaryEntry?) {
        _draft = State(initialValue: diary ?? DiaryEntry())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        DatePicker("日期", selection: $draft.date, displayedComponents: .date)
                        Picker("心情", selection: $draft.mood) {
                            ForEach(moods, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("标题", text: $draft.title)
                            .font(.title3)
                    }
                }
                .formStyle(.grouped)
                .frame(height: 190)

                Divider()

                TextEditor(text: $draft.body)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(18)
                    .focused($bodyFocused)
                    .accessibilityLabel("日记正文")
            }
            .navigationTitle(store.diary(id: draft.id) == nil ? "写日记" : "编辑日记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.upsert(draft)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 680, height: 620)
        .onAppear { bodyFocused = true }
    }
}

struct MonthPlanEditorView: View {
    @Environment(WorkbenchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let monthKey: String
    @State private var content: String

    init(monthKey: String) {
        self.monthKey = monthKey
        _content = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $content)
                .font(.body)
                .padding(18)
                .navigationTitle("\(monthKey) 月度计划")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            store.setMonthPlan(content, for: monthKey)
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(width: 560, height: 420)
        .onAppear { content = store.monthPlan(for: monthKey) }
    }
}
