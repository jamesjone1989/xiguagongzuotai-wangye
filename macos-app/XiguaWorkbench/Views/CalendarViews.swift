import SwiftUI

struct MonthCalendarView: View {
    @Environment(WorkbenchStore.self) private var store
    @Binding var selectedDate: Date
    let present: (SheetDestination) -> Void
    @State private var displayedMonth: Date

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    init(selectedDate: Binding<Date>, present: @escaping (SheetDestination) -> Void) {
        _selectedDate = selectedDate
        self.present = present
        _displayedMonth = State(initialValue: Calendar.current.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start ?? selectedDate.wrappedValue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            monthGrid
                .frame(minWidth: 560, maxWidth: .infinity)
            dayDetail
                .frame(width: 330)
        }
        .padding(28)
    }

    private var monthGrid: some View {
        VStack(spacing: 16) {
                HStack {
                    PageHeading(eyebrow: "MONTH", title: DateFormatting.monthTitle.string(from: displayedMonth))
                    Spacer()
                    Button { changeMonth(-1) } label: { Image(systemName: "arrow.left") }
                        .buttonStyle(SquareBrandButtonStyle())
                    Button("本月") {
                        displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
                        selectedDate = .now
                    }
                    .buttonStyle(OutlineButtonStyle())
                    Button { changeMonth(1) } label: { Image(systemName: "arrow.right") }
                        .buttonStyle(SquareBrandButtonStyle())
                    let key = DateFormatting.monthKey.string(from: displayedMonth)
                    Button {
                        present(.monthPlan(key))
                    } label: {
                        Text(store.monthPlan(for: key).isEmpty ? "添加计划" : "编辑计划")
                    }
                    .buttonStyle(OutlineButtonStyle())
                }

                let key = DateFormatting.monthKey.string(from: displayedMonth)
                if !store.monthPlan(for: key).isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "pin.fill").foregroundStyle(Color.workbenchGreen)
                        Text(store.monthPlan(for: key))
                            .lineLimit(3)
                        Spacer()
                    }
                    .font(.callout)
                    .padding(12)
                    .background(WorkbenchTheme.yellow.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WorkbenchTheme.ink, lineWidth: 1.5))
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(monthCells) { cell in
                        dayCell(cell)
                    }
                }
        }
        .hardCard(radius: 22, shadow: 8, padding: 20)
    }

    private var dayDetail: some View {
        let dayTasks = store.tasks(on: selectedDate)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatting.longDate.string(from: selectedDate))
                    .font(.title2.weight(.semibold))
                Text("\(dayTasks.filter { !$0.isCompleted }.count) 项待完成")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Rectangle().fill(WorkbenchTheme.ink).frame(height: 2)

            if dayTasks.isEmpty {
                EmptyState(
                    systemImage: "calendar",
                    title: "这天还没有安排",
                    message: "双击日期或使用上方按钮添加任务。",
                    actionTitle: "新建任务"
                ) { present(.newTask(selectedDate)) }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(dayTasks) { task in
                            TaskRow(task: task) { present(.editTask(task.id)) }
                                .softCard(radius: 11, padding: 11)
                        }
                    }
                }
            }
        }
        .hardCard(radius: 22, shadow: 8, padding: 20)
    }

    private func dayCell(_ cell: MonthCell) -> some View {
        let isSelected = Calendar.current.isDate(cell.date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(cell.date)
        let dayTasks = store.tasks(on: cell.date)

        return Button {
            selectedDate = cell.date
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(cell.date.formatted(.dateTime.day()))
                        .font(.callout.weight(isToday ? .bold : .medium))
                    Spacer()
                    if !dayTasks.isEmpty {
                        Text("\(dayTasks.count)")
                            .font(.caption2.weight(.bold))
                            .padding(5)
                            .background(Color.workbenchYellow, in: Circle())
                            .foregroundStyle(.black)
                    }
                }

                ForEach(dayTasks.prefix(2)) { task in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(task.isCompleted ? Color.secondary : Color.workbenchGreen)
                            .frame(width: 5, height: 5)
                        Text(task.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .strikethrough(task.isCompleted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(isSelected ? WorkbenchTheme.yellow : WorkbenchTheme.paperLight, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(WorkbenchTheme.ink, lineWidth: isSelected ? 2 : 1)
            }
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(WorkbenchTheme.ink)
                        .offset(x: 3, y: 3)
                }
            }
            .opacity(cell.isInDisplayedMonth ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { present(.newTask(cell.date)) })
        .accessibilityLabel("\(cell.date.formatted(date: .long, time: .omitted))，\(dayTasks.count) 项任务")
    }

    private var monthCells: [MonthCell] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let monthStart = monthInterval.start
        let weekday = calendar.component(.weekday, from: monthStart)
        let mondayOffset = (weekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -mondayOffset, to: monthStart) ?? monthStart

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return MonthCell(
                id: DateFormatting.dateKey.string(from: date),
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
            )
        }
    }

    private func changeMonth(_ amount: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) ?? displayedMonth
        selectedDate = displayedMonth
    }
}

private struct MonthCell: Identifiable {
    let id: String
    let date: Date
    let isInDisplayedMonth: Bool
}

struct YearOverviewView: View {
    @Environment(WorkbenchStore.self) private var store
    let present: (SheetDestination) -> Void
    @State private var year = Calendar.current.component(.year, from: .now)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    PageHeading(
                        eyebrow: "YEAR",
                        title: "\(year) 年",
                        subtitle: "把十二个月放在同一张地图上。"
                    )
                    Spacer()
                    Button { year -= 1 } label: { Image(systemName: "arrow.left") }
                        .buttonStyle(SquareBrandButtonStyle())
                    Button("今年") { year = Calendar.current.component(.year, from: .now) }
                        .buttonStyle(OutlineButtonStyle())
                    Button { year += 1 } label: { Image(systemName: "arrow.right") }
                        .buttonStyle(SquareBrandButtonStyle())
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(1...12, id: \.self) { month in
                        monthCard(month)
                    }
                }
            }
            .padding(28)
        }
    }

    private func monthCard(_ month: Int) -> some View {
        let components = DateComponents(year: year, month: month, day: 1)
        let date = Calendar.current.date(from: components) ?? .now
        let key = DateFormatting.monthKey.string(from: date)
        let tasks = store.tasks(in: date)
        let plan = store.monthPlan(for: key)

        return Button {
            present(.monthPlan(key))
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(month)月")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text("\(tasks.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if plan.isEmpty {
                    Label("添加月度计划", systemImage: "plus.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(plan)
                        .font(.callout)
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                ProgressView(value: tasks.isEmpty ? 0 : Double(tasks.filter(\.isCompleted).count), total: Double(max(tasks.count, 1)))
                    .tint(.workbenchGreen)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .softCard(fill: month % 3 == 0 ? WorkbenchTheme.sage : WorkbenchTheme.paperLight, radius: 14, padding: 16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(WorkbenchTheme.ink.opacity(0.3))
                    .offset(x: 3, y: 3)
            }
        }
        .buttonStyle(.plain)
    }
}
