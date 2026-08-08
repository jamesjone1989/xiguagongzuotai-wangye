import SwiftUI

struct BriefView: View {
    @Environment(WorkbenchStore.self) private var store
    @State private var aiAnalysis: WeeklyBriefAnalysis?
    @State private var isGenerating = false

    private var weekInterval: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)
    }

    private var weekTasks: [WorkbenchTask] {
        guard let weekInterval else { return [] }
        return store.tasks.filter { task in
            guard let date = task.date else { return false }
            return weekInterval.contains(date)
        }
    }

    private var completed: [WorkbenchTask] { weekTasks.filter(\.isCompleted) }
    private var pending: [WorkbenchTask] { weekTasks.filter { !$0.isCompleted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeading(
                        eyebrow: "WEEKLY BRIEF",
                        title: "本周简报",
                        subtitle: "用真实完成的事情，回看这一周。"
                    )
                    Spacer()
                    Button {
                        Task { await generateAIAnalysis() }
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating { ProgressView().controlSize(.small) }
                            Image(systemName: "sparkles")
                            Text(isGenerating ? "正在归类…" : "AI归类整理本周")
                        }
                    }
                    .buttonStyle(SolidButtonStyle(fill: WorkbenchTheme.green))
                    .disabled(isGenerating || weekTasks.isEmpty)
                }

                HStack(spacing: 14) {
                    metric(title: "本周任务", value: weekTasks.count, systemImage: "list.bullet", fill: WorkbenchTheme.yellow)
                    metric(title: "已完成", value: completed.count, systemImage: "checkmark.circle", fill: WorkbenchTheme.sage)
                    metric(title: "待推进", value: pending.count, systemImage: "arrow.forward.circle", fill: WorkbenchTheme.redSoft)
                    metric(title: "日记", value: recentDiaries.count, systemImage: "book.closed", fill: WorkbenchTheme.paperLight)
                }

                briefSection(title: "这一周完成了什么", tasks: completed, empty: "这一周还没有标记完成的任务。")
                briefSection(title: "接下来要继续推进", tasks: pending, empty: "本周没有遗留任务。")

                if let aiAnalysis {
                    aiAnalysisView(aiAnalysis)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("留给自己的问题", systemImage: "quote.bubble")
                        .font(.title3.weight(.semibold))
                    Text("这一周，哪一件事最值得继续？哪一件事其实可以放下？")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .workbenchPanel()
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private func aiAnalysisView(_ analysis: WeeklyBriefAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("DeepSeek 分类整理", systemImage: "sparkles")
                    .font(WorkbenchTheme.displayFont(24))
                Spacer()
                Button("重新整理") { Task { await generateAIAnalysis() } }
                    .buttonStyle(OutlineButtonStyle())
            }
            Text(analysis.summary)
                .font(.system(size: 15, weight: .medium))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(analysis.groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(group.title)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(WorkbenchTheme.green)
                        ForEach(group.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 7) {
                                Circle().fill(WorkbenchTheme.yellow).frame(width: 7, height: 7).padding(.top, 5)
                                Text(item).font(.system(size: 12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .softCard(radius: 13, padding: 14)
                }
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "scope").foregroundStyle(WorkbenchTheme.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("下周重点").font(.system(size: 12, weight: .heavy))
                    Text(analysis.nextFocus).font(.system(size: 13))
                }
            }
        }
        .hardCard(fill: WorkbenchTheme.sage, radius: 18, shadow: 6, padding: 20)
    }

    private var recentDiaries: [DiaryEntry] {
        guard let weekInterval else { return [] }
        return store.diaryEntries.filter { weekInterval.contains($0.date) }
    }

    private func metric(title: String, value: Int, systemImage: String, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.workbenchGreen)
                .font(.title2)
            Text("\(value)").font(WorkbenchTheme.displayFont(34))
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(fill: fill, radius: 15, padding: 16)
    }

    private func briefSection(title: String, tasks: [WorkbenchTask], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            if tasks.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.workbenchGreen)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(.body.weight(.medium))
                            if !task.notes.isEmpty {
                                Text(task.notes).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) { store.deleteTask(task.id) } label: {
                            Image(systemName: "trash").foregroundStyle(WorkbenchTheme.red)
                        }
                        .buttonStyle(.plain)
                        .help("删除任务")
                    }
                }
            }
        }
        .hardCard(radius: 18, shadow: 6, padding: 18)
    }

    @MainActor
    private func generateAIAnalysis() async {
        let key = KeychainStore.readDeepSeekKey()
        guard !key.isEmpty else {
            store.notice = "请先在设置中填写 DeepSeek API Key"
            return
        }
        guard !weekTasks.isEmpty else {
            store.notice = "本周还没有任务可以整理"
            return
        }
        let material = weekTasks.map { task in
            let date = task.date.map(DateFormatting.dateKey.string) ?? "无日期"
            return "- [\(task.isCompleted ? "已完成" : "待推进")] \(date)｜\(task.tag.rawValue)｜\(task.title)｜\(task.notes)"
        }.joined(separator: "\n")

        isGenerating = true
        defer { isGenerating = false }
        do {
            aiAnalysis = try await DeepSeekService.shared.generateWeeklyBrief(taskMaterial: material, apiKey: key)
            store.notice = "本周工作已经按主题归类"
        } catch {
            store.notice = error.localizedDescription
        }
    }
}
