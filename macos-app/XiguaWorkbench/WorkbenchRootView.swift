import SwiftUI

enum SheetDestination: Identifiable {
    case newTask(Date?)
    case editTask(UUID)
    case newDiary
    case editDiary(UUID)
    case monthPlan(String)

    var id: String {
        switch self {
        case .newTask: "new-task"
        case .editTask(let id): "task-\(id)"
        case .newDiary: "new-diary"
        case .editDiary(let id): "diary-\(id)"
        case .monthPlan(let key): "month-\(key)"
        }
    }
}

struct WorkbenchRootView: View {
    @Environment(WorkbenchStore.self) private var store
    @State private var selection: AppSection = .today
    @State private var selectedDate = Date.now
    @State private var sheet: SheetDestination?

    var body: some View {
        ZStack {
            PaperBackground()

            HStack(spacing: 0) {
                BrandSidebar(selection: $selection)
                .frame(width: 250)

                Rectangle()
                    .fill(WorkbenchTheme.ink)
                    .frame(width: 2)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(WorkbenchTheme.ink)
        .frame(minWidth: 980, minHeight: 650)
        .sheet(item: $sheet) { destination in
            sheetContent(for: destination)
                .preferredColorScheme(.light)
        }
        .focusedSceneValue(\.newWorkbenchTask) {
            sheet = .newTask(selectedDate)
        }
        .focusedSceneValue(\.newDiaryEntry) {
            sheet = .newDiary
        }
        .overlay(alignment: .bottomTrailing) {
            if let notice = store.notice {
                Text(notice)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WorkbenchTheme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(WorkbenchTheme.yellow)
                    .overlay(Rectangle().stroke(WorkbenchTheme.ink, lineWidth: 2))
                    .padding(22)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2.2))
                        if store.notice == notice { store.notice = nil }
                    }
            }
        }
        .animation(.snappy, value: store.notice)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today:
            TodayView(selectedDate: $selectedDate) { destination in sheet = destination }
        case .month:
            MonthCalendarView(selectedDate: $selectedDate) { destination in sheet = destination }
        case .year:
            YearOverviewView { destination in sheet = destination }
        case .agenda:
            AgendaView { destination in sheet = destination }
        case .inbox:
            InboxView { destination in sheet = destination }
        case .diary:
            DiaryView { destination in sheet = destination }
        case .brief:
            BriefView()
        case .settings:
            SettingsDashboardView()
        }
    }

    @ViewBuilder
    private func sheetContent(for destination: SheetDestination) -> some View {
        switch destination {
        case .newTask(let date):
            TaskEditorView(task: nil, suggestedDate: date).environment(store)
        case .editTask(let id):
            if let task = store.task(id: id) {
                TaskEditorView(task: task, suggestedDate: nil).environment(store)
            }
        case .newDiary:
            DiaryEditorView(diary: nil).environment(store)
        case .editDiary(let id):
            if let diary = store.diary(id: id) {
                DiaryEditorView(diary: diary).environment(store)
            }
        case .monthPlan(let key):
            MonthPlanEditorView(monthKey: key).environment(store)
        }
    }
}

private struct BrandSidebar: View {
    @Binding var selection: AppSection

    private let items: [(AppSection, String, String)] = [
        (.today, "今天", "此刻"),
        (.year, "年历", "全年"),
        (.month, "月历", "全月"),
        (.agenda, "日程", "一天"),
        (.brief, "简报", "一周"),
        (.diary, "日记", "回声"),
        (.settings, "设置", "云端"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                WatermelonBrandMark()
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("西瓜老师")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(0.6)
                    Text("个人工作台")
                        .font(.system(size: 11))
                        .tracking(2)
                        .foregroundStyle(WorkbenchTheme.muted)
                }
            }
            .padding(.top, 30)

            VStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.element.0) { index, item in
                    sidebarButton(number: index + 1, section: item.0, title: item.1, trailing: item.2)
                }

            }
            .padding(.top, 54)

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 7) {
                Rectangle().fill(WorkbenchTheme.ink).frame(height: 2)
                Text("今日提醒")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.7)
                    .foregroundStyle(WorkbenchTheme.red)
                    .padding(.top, 10)
                Text("把复杂的事，放回一小步。")
                    .font(.custom("Songti SC", size: 17))
                    .lineSpacing(5)
            }
            .padding(.bottom, 25)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkbenchTheme.paperLight.opacity(0.94))
    }

    private func sidebarButton(number: Int, section: AppSection, title: String, trailing: String) -> some View {
        Button {
            selection = section
        } label: {
            SidebarRow(number: number, title: title, trailing: trailing, isSelected: selection == section)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SidebarRow: View {
    let number: Int
    let title: String
    let trailing: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "%02d", number))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(isSelected ? WorkbenchTheme.green : WorkbenchTheme.muted)
                .frame(width: 28, alignment: .leading)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(trailing)
                .font(.system(size: 11))
                .foregroundStyle(WorkbenchTheme.muted)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(isSelected ? WorkbenchTheme.yellow : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12).stroke(WorkbenchTheme.ink, lineWidth: 2)
            }
        }
    }
}

private struct WatermelonBrandMark: View {
    var body: some View {
        ZStack {
            Circle().fill(WorkbenchTheme.red).overlay(Circle().stroke(WorkbenchTheme.ink, lineWidth: 2))
            HStack(spacing: 12) {
                Capsule().fill(WorkbenchTheme.ink).frame(width: 4, height: 7).rotationEffect(.degrees(18))
                Capsule().fill(WorkbenchTheme.ink).frame(width: 4, height: 7).rotationEffect(.degrees(-18))
            }
            SmileShape()
                .stroke(WorkbenchTheme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 18, height: 10)
                .offset(y: 8)
        }
        .rotationEffect(.degrees(-7))
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}
