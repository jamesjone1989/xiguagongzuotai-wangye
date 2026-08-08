import SwiftUI

struct DiaryView: View {
    @Environment(WorkbenchStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    let present: (SheetDestination) -> Void

    @State private var selectedDiaryID: UUID?
    @State private var searchText = ""
    @State private var diaryInput = ""
    @State private var mode: Mode = .echo
    @State private var isThinking = false
    @State private var confirmNewConversation = false

    private enum Mode: Equatable { case echo, archive }

    private var filteredDiaries: [DiaryEntry] {
        guard !searchText.isEmpty else { return store.diaryEntries }
        return store.diaryEntries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.body.localizedCaseInsensitiveContains(searchText)
                || $0.mood.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedDiary: DiaryEntry? {
        if let selectedDiaryID, let diary = store.diary(id: selectedDiaryID) { return diary }
        return filteredDiaries.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            diaryShelf.frame(width: 330)
            Group {
                if mode == .echo { echoConversation } else { diaryDetail }
            }
            .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(28)
        .confirmationDialog("开始新的回声对话？", isPresented: $confirmNewConversation) {
            Button("清空当前对话并开始", role: .destructive) { store.resetDiaryConversation() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已经保存的日记不会受到影响。")
        }
    }

    private var diaryShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeading(eyebrow: "ECHO DIARY", title: "回声日记", subtitle: "先聊清楚，再写下来。")

            HStack(spacing: 8) {
                modeButton("回声对话", target: .echo)
                modeButton("往期日记", target: .archive)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(WorkbenchTheme.green)
                TextField("搜索日记", text: $searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchTheme.ink, lineWidth: 1.5))

            HStack {
                Text("已经收好的日记")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(WorkbenchTheme.green)
                Spacer()
                Button { present(.newDiary) } label: { Image(systemName: "plus") }
                    .buttonStyle(SquareBrandButtonStyle())
                    .help("手写一篇日记")
            }

            if filteredDiaries.isEmpty {
                EmptyState(
                    systemImage: "book.closed",
                    title: searchText.isEmpty ? "还没有日记" : "没有找到",
                    message: searchText.isEmpty ? "和西瓜老师聊几句，生成第一篇。" : "换个关键词再试试。"
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredDiaries) { diary in
                            Button {
                                selectedDiaryID = diary.id
                                mode = .archive
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(diary.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                                        Spacer()
                                        Text(diary.mood).font(.system(size: 10, weight: .bold)).foregroundStyle(WorkbenchTheme.green)
                                    }
                                    Text(diary.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(WorkbenchTheme.muted)
                                    Text(diary.body).font(.callout).foregroundStyle(WorkbenchTheme.muted).lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .softCard(
                                    fill: selectedDiary?.id == diary.id && mode == .archive ? WorkbenchTheme.yellow : WorkbenchTheme.paperLight,
                                    radius: 12,
                                    padding: 12
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .hardCard(radius: 22, shadow: 8, padding: 18)
    }

    private func modeButton(_ title: String, target: Mode) -> some View {
        Button(title) { mode = target }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(WorkbenchTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(mode == target ? WorkbenchTheme.yellow : WorkbenchTheme.paperLight, in: Capsule())
            .overlay(Capsule().stroke(WorkbenchTheme.ink, lineWidth: 1.8))
    }

    private var echoConversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PageHeading(
                    eyebrow: "CONVERSATION",
                    title: "对话日记",
                    subtitle: "西瓜老师会追问具体经过，只用你说过的信息整理日记。"
                )
                Spacer()
                Button("新建对话") { confirmNewConversation = true }
                    .buttonStyle(OutlineButtonStyle())
                Button("生成日记") { Task { await generateDiary() } }
                    .buttonStyle(SolidButtonStyle(fill: WorkbenchTheme.green))
                    .disabled(isThinking || store.diaryMessages.allSatisfy { $0.role != "user" })
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.diaryMessages) { message in
                        HStack {
                            if message.role == "user" { Spacer(minLength: 90) }
                            Text(message.content)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .foregroundStyle(WorkbenchTheme.ink)
                                .softCard(
                                    fill: message.role == "assistant" ? WorkbenchTheme.sage : WorkbenchTheme.yellow,
                                    radius: 15,
                                    padding: 14
                                )
                            if message.role == "assistant" { Spacer(minLength: 90) }
                        }
                    }

                    if isThinking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("西瓜老师正在想下一句……")
                                .font(.system(size: 12))
                                .foregroundStyle(WorkbenchTheme.muted)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 12) {
                TextField("说说今天发生的一件具体事情……", text: $diaryInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
                    .padding(14)
                    .background(WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(WorkbenchTheme.ink, lineWidth: 2))
                    .onSubmit { Task { await sendMessage() } }

                Button("发送") { Task { await sendMessage() } }
                    .buttonStyle(SolidButtonStyle(fill: WorkbenchTheme.green))
                    .disabled(diaryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            }

            if KeychainStore.readDeepSeekKey().isEmpty {
                HStack {
                    Text("对话日记需要 DeepSeek API Key。")
                        .font(.system(size: 12)).foregroundStyle(WorkbenchTheme.muted)
                    Button("去设置") { openSettings() }
                        .buttonStyle(.link)
                }
            }
        }
        .hardCard(radius: 22, shadow: 8, padding: 22)
    }

    @ViewBuilder
    private var diaryDetail: some View {
        if let diary = selectedDiary {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(diary.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                                .font(.callout).foregroundStyle(WorkbenchTheme.green)
                            Text(diary.title).font(WorkbenchTheme.displayFont(38))
                            Text("心情 · \(diary.mood)").font(.callout).foregroundStyle(WorkbenchTheme.green)
                        }
                        Spacer()
                        Menu {
                            Button("编辑") { present(.editDiary(diary.id)) }
                            Button("删除", role: .destructive) { store.deleteDiary(diary.id) }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                    }

                    Rectangle().fill(WorkbenchTheme.ink).frame(height: 2)
                    Text(diary.body).font(.body).lineSpacing(6).textSelection(.enabled)
                }
                .padding(36)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .hardCard(radius: 22, shadow: 8, padding: 0)
        } else {
            EmptyState(systemImage: "book.closed", title: "还没有日记", message: "切到回声对话，从一件具体事情开始。")
                .hardCard(radius: 22, shadow: 8, padding: 18)
        }
    }

    @MainActor
    private func sendMessage() async {
        let value = diaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isThinking else { return }
        let key = KeychainStore.readDeepSeekKey()
        guard !key.isEmpty else {
            store.notice = "请先在设置中填写 DeepSeek API Key"
            openSettings()
            return
        }

        let userMessage = ChatMessage(role: "user", content: value)
        store.addDiaryMessage(userMessage)
        diaryInput = ""
        isThinking = true
        defer { isThinking = false }
        do {
            let content = try await DeepSeekService.shared.diaryReply(messages: store.diaryMessages, apiKey: key)
            store.addDiaryMessage(ChatMessage(role: "assistant", content: content.isEmpty ? "然后发生了什么？" : content))
        } catch {
            store.notice = error.localizedDescription
        }
    }

    @MainActor
    private func generateDiary() async {
        let key = KeychainStore.readDeepSeekKey()
        guard !key.isEmpty else {
            store.notice = "请先在设置中填写 DeepSeek API Key"
            openSettings()
            return
        }
        guard store.diaryMessages.contains(where: { $0.role == "user" }) else {
            store.notice = "先聊几句，再生成日记"
            return
        }

        isThinking = true
        defer { isThinking = false }
        do {
            let generated = try await DeepSeekService.shared.generateDiary(messages: store.diaryMessages, apiKey: key)
            let diary = DiaryEntry(date: .now, title: generated.title, body: generated.body, mood: "平静")
            store.upsert(diary)
            selectedDiaryID = diary.id
            mode = .archive
            store.notice = "回声日记已经生成并保存"
        } catch {
            store.notice = error.localizedDescription
        }
    }
}
