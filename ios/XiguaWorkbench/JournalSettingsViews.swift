import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiaryEntry.updatedAt, order: .reverse) private var entries: [DiaryEntry]
    @State private var searchText = ""
    @State private var editorRoute: DiaryEditorRoute?

    private var filteredEntries: [DiaryEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "还没有日记" : "没有找到日记",
                    systemImage: searchText.isEmpty ? "book.closed" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "写下一件今天真实发生的事就够了。" : "试试其他关键词。")
                )
            } else {
                ForEach(filteredEntries) { entry in
                    Button {
                        editorRoute = DiaryEditorRoute(entry: entry)
                    } label: {
                        DiaryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
        .navigationTitle("日记")
        .searchable(text: $searchText, prompt: "搜索日记")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = DiaryEditorRoute(entry: nil)
                } label: {
                    Label("写日记", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            DiaryEditorView(entry: route.entry)
        }
    }
}

private struct DiaryRow: View {
    let entry: DiaryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.mood)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title.isEmpty ? "未命名日记" : entry.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(entry.body.isEmpty ? "没有正文" : entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

struct DiaryEditorView: View {
    private static let moods = ["平静", "开心", "充实", "疲惫", "低落", "期待"]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: DiaryEntry?
    @State private var date: Date
    @State private var title: String
    @State private var bodyText: String
    @State private var mood: String
    @State private var isPolishing = false
    @State private var alertMessage: String?
    @State private var showingDeleteConfirmation = false
    @FocusState private var titleFocused: Bool

    init(entry: DiaryEntry?) {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? .now)
        _title = State(initialValue: entry?.title ?? "")
        _bodyText = State(initialValue: entry?.body ?? "")
        _mood = State(initialValue: entry?.mood ?? "平静")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("心情", selection: $mood) {
                        ForEach(Self.moods, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("标题") {
                    TextField("今天最想记住什么？", text: $title)
                        .focused($titleFocused)
                }

                Section("正文") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 260)

                    Button {
                        polishWithAI()
                    } label: {
                        if isPolishing {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("正在整理…")
                            }
                        } else {
                            Label("AI 帮我整理表达", systemImage: "sparkles")
                        }
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPolishing)
                }

                if entry != nil {
                    Section {
                        Button("删除日记", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "写日记" : "编辑日记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .confirmationDialog("确定删除这篇日记吗？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("删除日记", role: .destructive) { deleteEntry() }
                Button("取消", role: .cancel) {}
            }
            .onAppear { if entry == nil { titleFocused = true } }
        }
    }

    private func polishWithAI() {
        let apiKey = KeychainStore.loadAPIKey()
        guard !apiKey.isEmpty else {
            alertMessage = "请先到“设置”中保存 DeepSeek API Key。"
            return
        }
        isPolishing = true
        Task {
            defer { isPolishing = false }
            do {
                bodyText = try await DeepSeekService.polishDiary(bodyText, apiKey: apiKey)
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription ?? "AI 整理失败，请稍后再试。"
            }
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.date = date
            entry.title = cleanTitle
            entry.body = cleanBody
            entry.mood = mood
            entry.updatedAt = .now
        } else {
            modelContext.insert(DiaryEntry(date: date, title: cleanTitle, body: cleanBody, mood: mood))
        }
        try? modelContext.save()
        dismiss()
    }

    private func deleteEntry() {
        if let entry { modelContext.delete(entry) }
        try? modelContext.save()
        dismiss()
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [WorkbenchTask]
    @Query private var diaries: [DiaryEntry]
    @Query private var notes: [MonthlyNote]

    @State private var apiKey = ""
    @State private var backupDocument = WorkbenchBackupDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingBackup: WorkbenchBackup?
    @State private var showingRestoreConfirmation = false
    @State private var showingRemoveKeyConfirmation = false
    @State private var alertTitle = ""
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField("sk-…", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("保存到钥匙串") { saveAPIKey() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !KeychainStore.loadAPIKey().isEmpty {
                    Button("移除 API Key", role: .destructive) {
                        showingRemoveKeyConfirmation = true
                    }
                }
            } header: {
                Text("DeepSeek")
            } footer: {
                Text("API Key 仅保存在系统钥匙串中，不会进入数据备份。AI 生成内容必须由你确认后保存。")
            }

            Section("数据") {
                Button {
                    exportBackup()
                } label: {
                    Label("导出 JSON 备份", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("从备份恢复", systemImage: "square.and.arrow.down")
                }

                LabeledContent("任务", value: "\(tasks.count)")
                LabeledContent("日记", value: "\(diaries.count)")
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0")
                Link(destination: URL(string: "https://xigua-personal-workbench.jone19890801.chatgpt.site")!) {
                    Label("打开原网页版", systemImage: "safari")
                }
                NavigationLink("隐私说明") {
                    PrivacyView()
                }
            }
        }
        .navigationTitle("设置")
        .onAppear { apiKey = KeychainStore.loadAPIKey() }
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "西瓜工作台备份-\(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result {
                showAlert("导出失败", error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .confirmationDialog("恢复备份会覆盖当前 App 内的数据", isPresented: $showingRestoreConfirmation, titleVisibility: .visible) {
            Button("覆盖并恢复", role: .destructive) { restoreBackup() }
            Button("取消", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("API Key 不受影响。建议先导出一次当前数据。")
        }
        .confirmationDialog("移除 API Key？", isPresented: $showingRemoveKeyConfirmation, titleVisibility: .visible) {
            Button("移除", role: .destructive) { removeAPIKey() }
            Button("取消", role: .cancel) {}
        }
        .alert(alertTitle, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func saveAPIKey() {
        do {
            let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainStore.saveAPIKey(cleanKey)
            apiKey = cleanKey
            showAlert("已保存", "API Key 已安全保存到系统钥匙串。")
        } catch {
            showAlert("保存失败", error.localizedDescription)
        }
    }

    private func removeAPIKey() {
        do {
            try KeychainStore.deleteAPIKey()
            apiKey = ""
        } catch {
            showAlert("移除失败", error.localizedDescription)
        }
    }

    private func exportBackup() {
        do {
            backupDocument = WorkbenchBackupDocument(data: try BackupService.encode(tasks: tasks, diaries: diaries, notes: notes))
            isExporting = true
        } catch {
            showAlert("导出失败", error.localizedDescription)
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            pendingBackup = try BackupService.decode(Data(contentsOf: url))
            showingRestoreConfirmation = true
        } catch {
            showAlert("读取失败", "这个文件不是有效的西瓜工作台备份。")
        }
    }

    private func restoreBackup() {
        guard let pendingBackup else { return }
        do {
            try BackupService.restore(pendingBackup, in: modelContext)
            self.pendingBackup = nil
            showAlert("恢复完成", "任务、日记和月度计划已经恢复。")
        } catch {
            showAlert("恢复失败", error.localizedDescription)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section("数据保存") {
                Text("任务、月度计划和日记由 SwiftData 保存在当前设备。导出备份时不会包含 DeepSeek API Key。")
            }
            Section("AI") {
                Text("只有在你主动点击 AI 功能时，当前输入的任务或日记文本才会发送给 DeepSeek。AI 返回内容不会自动覆盖你的记录。")
            }
            Section("密钥") {
                Text("DeepSeek API Key 保存于 iOS 钥匙串，并可随时在设置中移除。")
            }
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
