import SwiftUI

struct DiaryView: View {
    @Environment(WorkbenchStore.self) private var store
    let present: (SheetDestination) -> Void
    @State private var selectedDiaryID: UUID?
    @State private var searchText = ""

    private var filteredDiaries: [DiaryEntry] {
        guard !searchText.isEmpty else { return store.diaryEntries }
        return store.diaryEntries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.body.localizedCaseInsensitiveContains(searchText)
                || $0.mood.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedDiary: DiaryEntry? {
        if let selectedDiaryID, let diary = store.diary(id: selectedDiaryID) {
            return diary
        }
        return filteredDiaries.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            diaryList
                .frame(width: 330)
            diaryDetail
                .frame(minWidth: 470, maxWidth: .infinity)
        }
        .padding(28)
    }

    private var diaryList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PageHeading(eyebrow: "DIARY", title: "回声日记", subtitle: "具体地记下一件发生过的事。")
                Spacer()
                Button { present(.newDiary) } label: { Image(systemName: "plus") }
                    .buttonStyle(SquareBrandButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(WorkbenchTheme.green)
                TextField("搜索日记", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchTheme.ink, lineWidth: 1.5))

            if filteredDiaries.isEmpty {
                EmptyState(
                    systemImage: "book.closed",
                    title: searchText.isEmpty ? "还没有日记" : "没有找到相关日记",
                    message: searchText.isEmpty ? "不必写完整，从一个具体瞬间开始。" : "换个关键词再试试。",
                    actionTitle: searchText.isEmpty ? "写第一篇" : nil,
                    action: searchText.isEmpty ? { present(.newDiary) } : nil
                )
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredDiaries) { diary in
                            Button {
                                selectedDiaryID = diary.id
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(diary.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                                        Spacer()
                                        Text(diary.mood).font(.system(size: 10, weight: .bold)).foregroundStyle(WorkbenchTheme.green)
                                    }
                                    Text(diary.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(WorkbenchTheme.muted)
                                    Text(diary.body)
                                        .font(.callout)
                                        .foregroundStyle(WorkbenchTheme.muted)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .softCard(
                                    fill: selectedDiary?.id == diary.id ? WorkbenchTheme.yellow : WorkbenchTheme.paperLight,
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

    @ViewBuilder
    private var diaryDetail: some View {
        if let diary = selectedDiary {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(diary.date.formatted(.dateTime.year().month().day().weekday(.wide)))
                                .font(.callout)
                                .foregroundStyle(WorkbenchTheme.green)
                            Text(diary.title)
                                .font(WorkbenchTheme.displayFont(38))
                            Text("心情 · \(diary.mood)")
                                .font(.callout)
                                .foregroundStyle(Color.workbenchGreen)
                        }
                        Spacer()
                        Menu {
                            Button("编辑") { present(.editDiary(diary.id)) }
                            Button("删除", role: .destructive) { store.deleteDiary(diary.id) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                    }

                    Rectangle().fill(WorkbenchTheme.ink).frame(height: 2)

                    Text(diary.body)
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
                .padding(36)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .hardCard(radius: 22, shadow: 8, padding: 0)
        } else {
            EmptyState(systemImage: "book.closed", title: "选择一篇日记", message: "从左侧选择，或开始写一篇新的日记。")
                .hardCard(radius: 22, shadow: 8, padding: 18)
        }
    }
}
