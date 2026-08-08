import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DiaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiaryEntry.updatedAt, order: .reverse) private var entries: [DiaryEntry]
    @State private var searchText = ""
    @State private var editorRoute: DiaryEditorRoute?
    @State private var showingConversation = false

    private var filteredEntries: [DiaryEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    XiguaCard(fill: XiguaTheme.yellow) {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DIARY / CONVERSATION")
                                    .font(.caption2.weight(.black))
                                    .tracking(1.4)
                                    .foregroundStyle(XiguaTheme.green)
                                Text("不用急着写成文章，\n先聊聊今天。")
                                    .font(.title2.weight(.black))
                                    .foregroundStyle(XiguaTheme.ink)
                                Button { showingConversation = true } label: {
                                    Label("和西瓜老师聊一聊", systemImage: "bubble.left.and.bubble.right.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(XiguaFilledButtonStyle())
                            }
                            Image("XiguaTeacher")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 96, height: 116, alignment: .bottom)
                                .accessibilityHidden(true)
                        }
                    }

                    SectionHeading(
                        eyebrow: "MEMORY / ARCHIVE",
                        title: "最近的日记",
                        detail: "\(filteredEntries.count) 篇"
                    )

                    if filteredEntries.isEmpty {
                        XiguaCard(fill: XiguaTheme.sage) {
                            EmptyDiaryNote(isSearching: !searchText.isEmpty)
                        }
                    } else {
                        ForEach(filteredEntries) { entry in
                            XiguaCard {
                                Button {
                                    editorRoute = DiaryEditorRoute(entry: entry)
                                } label: {
                                    DiaryPaperRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("删除", role: .destructive) {
                                        modelContext.delete(entry)
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("日记")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索日记")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = DiaryEditorRoute(entry: nil)
                } label: {
                    Label("直接写", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            DiaryEditorView(
                entry: route.entry,
                initialTitle: route.initialTitle,
                initialBody: route.initialBody
            )
        }
        .fullScreenCover(isPresented: $showingConversation) {
            DiaryConversationView { title, body in
                showingConversation = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    editorRoute = DiaryEditorRoute(entry: nil, initialTitle: title, initialBody: body)
                }
            }
        }
    }
}

private struct DiaryPaperRow: View {
    let entry: DiaryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 2) {
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.title2.monospacedDigit().weight(.black))
                Text(entry.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(XiguaTheme.red)
            }
            .frame(width: 48)

            Rectangle().fill(XiguaTheme.line).frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.title.isEmpty ? "未命名日记" : entry.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(XiguaTheme.ink)
                    Spacer()
                    Text(entry.mood)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(XiguaTheme.sage, in: Capsule())
                        .foregroundStyle(XiguaTheme.green)
                }
                Text(entry.body.isEmpty ? "没有正文" : entry.body)
                    .font(.subheadline)
                    .foregroundStyle(XiguaTheme.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(XiguaTheme.muted)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
    }
}

private struct EmptyDiaryNote: View {
    let isSearching: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "book.closed")
                .font(.title2.weight(.bold))
                .foregroundStyle(XiguaTheme.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(isSearching ? "没有找到日记" : "还没有日记")
                    .font(.headline.weight(.black))
                    .foregroundStyle(XiguaTheme.ink)
                Text(isSearching ? "换一个关键词试试。" : "写下一件今天真实发生的事就够了。")
                    .font(.subheadline)
                    .foregroundStyle(XiguaTheme.muted)
            }
            Spacer()
        }
    }
}

private struct DiaryChatMessage: Identifiable {
    enum Speaker: Equatable { case teacher, me }
    let id = UUID()
    let speaker: Speaker
    let text: String
}

struct DiaryConversationView: View {
    @Environment(\.dismiss) private var dismiss
    let onDraftReady: (String, String) -> Void

    private let prompts = [
        "今天发生了什么？先说一件你最想留下来的事。",
        "当时有哪个具体的细节，让你印象最深？",
        "那一刻，你真实的感受是什么？",
        "回头看，这件事对你意味着什么？"
    ]

    @State private var messages: [DiaryChatMessage] = [
        DiaryChatMessage(speaker: .teacher, text: "今天过得怎么样？不用组织语言，我们慢慢聊。")
    ]
    @State private var answers: [String] = []
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }
                                if answers.count >= prompts.count {
                                    DraftReadyCard { makeDraft() }
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: messages.count) {
                            if let last = messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }

                    if answers.count < prompts.count {
                        HStack(alignment: .bottom, spacing: 10) {
                            TextField("像聊天一样说就好…", text: $input, axis: .vertical)
                                .lineLimit(1 ... 4)
                                .focused($inputFocused)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(XiguaTheme.paperLight, in: RoundedRectangle(cornerRadius: 18))
                                .overlay { RoundedRectangle(cornerRadius: 18).stroke(XiguaTheme.ink, lineWidth: 1.5) }
                                .onSubmit(send)
                            Button(action: send) {
                                Image(systemName: "arrow.up")
                                    .font(.headline.weight(.black))
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(XiguaTheme.green, in: Circle())
                                    .overlay { Circle().stroke(XiguaTheme.ink, lineWidth: 1.5) }
                            }
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("发送")
                        }
                        .padding(12)
                        .background(XiguaTheme.paperLight)
                    }
                }
            }
            .navigationTitle("和西瓜老师聊聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
            .onAppear { inputFocused = true }
        }
    }

    private func send() {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        input = ""
        answers.append(clean)
        withAnimation(.snappy) {
            messages.append(DiaryChatMessage(speaker: .me, text: clean))
            if answers.count < prompts.count {
                messages.append(DiaryChatMessage(speaker: .teacher, text: prompts[answers.count]))
            } else {
                messages.append(DiaryChatMessage(speaker: .teacher, text: "我听明白了。事实、细节和感受都在，可以先生成一版草稿，再由你决定怎么写。"))
            }
        }
    }

    private func makeDraft() {
        let first = answers.first ?? "今天的一件事"
        let title = first.count > 18 ? String(first.prefix(18)) + "…" : first
        let labels = ["今天发生的事", "我记住的细节", "当时的感受", "现在回头看"]
        let body = zip(labels, answers).map { label, answer in
            "【\(label)】\n\(answer)"
        }.joined(separator: "\n\n")
        onDraftReady(title, body)
    }
}

private struct ChatBubble: View {
    let message: DiaryChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.speaker == .me { Spacer(minLength: 46) }
            if message.speaker == .teacher {
                Image("XiguaTeacher")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 44)
                    .accessibilityHidden(true)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(XiguaTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(message.speaker == .teacher ? XiguaTheme.yellow : XiguaTheme.sage, in: RoundedRectangle(cornerRadius: 17))
                .overlay { RoundedRectangle(cornerRadius: 17).stroke(XiguaTheme.ink, lineWidth: 1.5) }
            if message.speaker == .teacher { Spacer(minLength: 46) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DraftReadyCard: View {
    let action: () -> Void

    var body: some View {
        XiguaCard(fill: XiguaTheme.redSoft) {
            VStack(alignment: .leading, spacing: 10) {
                Label("素材已经够了", systemImage: "checkmark.seal.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(XiguaTheme.green)
                Text("先生成一版忠于事实的草稿。保存前，你仍然可以逐字修改。")
                    .font(.subheadline)
                    .foregroundStyle(XiguaTheme.muted)
                Button("生成日记草稿", action: action)
                    .buttonStyle(XiguaFilledButtonStyle())
            }
        }
        .padding(.top, 4)
    }
}

private struct LegacyDiaryView: View {
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

    init(entry: DiaryEntry?, initialTitle: String = "", initialBody: String = "") {
        self.entry = entry
        _date = State(initialValue: entry?.date ?? .now)
        _title = State(initialValue: entry?.title ?? initialTitle)
        _bodyText = State(initialValue: entry?.body ?? initialBody)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkbenchSyncController.self) private var syncController
    @Query private var tasks: [WorkbenchTask]
    @Query private var diaries: [DiaryEntry]
    @Query private var notes: [MonthlyNote]

    @State private var apiKey = ""
    @State private var syncKey = ""
    @State private var syncKeyVisible = false
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
                HStack {
                    Label(syncController.status.label, systemImage: syncStatusSymbol)
                        .foregroundStyle(syncStatusColor)
                    Spacer()
                    if let lastSyncedAt = syncController.lastSyncedAt {
                        Text(lastSyncedAt.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                Group {
                    if syncKeyVisible {
                        TextField("至少 32 位同步码", text: $syncKey)
                    } else {
                        SecureField("至少 32 位同步码", text: $syncKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    generateSyncKey()
                } label: {
                    Label("生成新的同步码", systemImage: "key.fill")
                }

                Button {
                    syncKeyVisible.toggle()
                } label: {
                    Label(syncKeyVisible ? "隐藏同步码" : "显示同步码", systemImage: syncKeyVisible ? "eye.slash" : "eye")
                }
                .disabled(syncKey.isEmpty)

                Button {
                    UIPasteboard.general.string = syncKey
                    showAlert("已复制", "请把同一个同步码粘贴到网页版“设置 → 跨设备同步”。")
                } label: {
                    Label("复制同步码", systemImage: "doc.on.doc")
                }
                .disabled(syncKey.count < 32)

                Button {
                    saveAndSync()
                } label: {
                    if syncController.status == .syncing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("正在同步…")
                        }
                    } else {
                        Label("保存并立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncKey.trimmingCharacters(in: .whitespacesAndNewlines).count < 32 || syncController.status == .syncing)

                if syncController.isConfigured {
                    Button("停止跨设备同步", role: .destructive) {
                        stopSync()
                    }
                }
            } header: {
                Text("跨设备同步")
            } footer: {
                Text("网页版和 iPhone 填写同一个同步码后，任务、待办箱、月度便签和日记会通过加密连接双向合并。同步码保存在系统钥匙串中；DeepSeek API Key 不会上传。")
            }

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
                LabeledContent(
                    "版本",
                    value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
                )
                Link(destination: URL(string: "https://xigua-personal-workbench.jone19890801.chatgpt.site")!) {
                    Label("打开原网页版", systemImage: "safari")
                }
                NavigationLink("隐私说明") {
                    PrivacyView()
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear {
            apiKey = KeychainStore.loadAPIKey()
            syncKey = KeychainStore.loadSyncKey()
        }
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

    private var syncStatusSymbol: String {
        switch syncController.status {
        case .local: "iphone"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.icloud.fill"
        case .error: "exclamationmark.icloud.fill"
        }
    }

    private var syncStatusColor: Color {
        switch syncController.status {
        case .local: .secondary
        case .syncing: XiguaTheme.yellow
        case .synced: XiguaTheme.green
        case .error: XiguaTheme.red
        }
    }

    private func generateSyncKey() {
        syncKey = "\(UUID().uuidString)\(UUID().uuidString)".replacingOccurrences(of: "-", with: "").lowercased()
        syncKeyVisible = true
    }

    private func saveAndSync() {
        let cleanKey = syncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKey.count >= 32 else {
            showAlert("同步码太短", "同步码至少需要 32 位。")
            return
        }
        do {
            try KeychainStore.saveSyncKey(cleanKey)
            syncKey = cleanKey
            Task {
                await syncController.sync(modelContext: modelContext)
                if case .error(let message) = syncController.status {
                    showAlert("同步失败", message)
                } else {
                    showAlert("同步完成", "网页版和 iPhone 数据已经合并。以后修改会自动同步。")
                }
            }
        } catch {
            showAlert("保存失败", error.localizedDescription)
        }
    }

    private func stopSync() {
        do {
            try syncController.disconnect()
            syncKey = ""
            syncKeyVisible = false
        } catch {
            showAlert("停止失败", error.localizedDescription)
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
                Text("任务、月度计划和日记由 SwiftData 保存在当前设备。启用跨设备同步后，这些记录也会保存到网页版使用的 Cloudflare D1 数据库。")
            }
            Section("AI") {
                Text("只有在你主动点击 AI 功能时，当前输入的任务或日记文本才会发送给 DeepSeek。AI 返回内容不会自动覆盖你的记录。")
            }
            Section("密钥") {
                Text("DeepSeek API Key 和跨平台同步码都保存在 iOS 钥匙串，并可随时在设置中移除。DeepSeek API Key 不参与同步。")
            }
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
