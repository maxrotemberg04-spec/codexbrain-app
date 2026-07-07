import SwiftUI

/// Apple-Calendar-style month grid over CALENDAR.md: click a day, add a colored
/// item, done. This week's day-tagged HOME.md tasks appear on their dates too.
struct CalendarView: View {
    @EnvironmentObject var state: AppState
    @State private var monthAnchor = Date()

    private var cal: Calendar { Calendar.current }

    static let monthTitleFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            weekdayHeader
            monthGrid
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(Theme.bg)
        .navigationTitle("")
        .toolbar { DashboardToolbar() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(Self.monthTitleFormat.string(from: monthAnchor))
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("CALENDAR.md · synced with the repo")
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textSecondary)
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Button("Today") { monthAnchor = Date() }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private func shift(_ months: Int) {
        monthAnchor = cal.date(byAdding: .month, value: months, to: monthAnchor) ?? monthAnchor
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.shortWeekdaySymbols   // Sun..Sat
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var weekdayHeader: some View {
        HStack(spacing: 8) {
            ForEach(weekdaySymbols, id: \.self) { day in
                Text(day.uppercased())
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Dates laid out for the month: nil = leading/trailing blank cells.
    private var gridDates: [Date?] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)),
              let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: monthStart)
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: day, to: monthStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var monthGrid: some View {
        let cells = gridDates
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    CalendarDayCell(date: date)
                } else {
                    Color.clear.frame(minHeight: 96)
                }
            }
        }
    }
}

struct CalendarDayCell: View {
    @EnvironmentObject var state: AppState
    let date: Date
    @State private var showDetail = false
    @State private var newText = ""
    @State private var newColor = "amber"
    @State private var hovering = false

    private var iso: String { CalendarDoc.iso.string(from: date) }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var dayNumber: String { "\(Calendar.current.component(.day, from: date))" }

    /// Dated CALENDAR.md items, plus this week's day-tagged HOME tasks on their dates.
    private var items: [CalItem] { state.calItems.filter { $0.date == iso } }
    private var homeTasks: [TaskLine] {
        guard let offset = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                           to: Calendar.current.startOfDay(for: date)).day,
              (0..<7).contains(offset) else { return [] }
        let dayName = Planner.nameFormat.string(from: date)
        return (state.home?.week ?? []).filter { $0.dayTag == dayName }
    }

    static func color(_ name: String) -> Color {
        switch name {
        case "teal": return GraphModel.palette[1]
        case "blue": return GraphModel.palette[2]
        case "rose": return GraphModel.palette[3]
        case "sage": return GraphModel.palette[4]
        case "lavender": return GraphModel.palette[5]
        default: return Theme.accent
        }
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dayNumber)
                        .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(isToday ? Color.black : Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(isToday ? Theme.accent : .clear))
                    Spacer()
                    if hovering {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ForEach(items.prefix(3)) { item in
                    entryRow(color: Self.color(item.color), text: item.text, done: item.done)
                }
                ForEach(homeTasks.prefix(2)) { task in
                    entryRow(color: Theme.textSecondary.opacity(0.7), text: task.textWithoutDayTag, done: task.done)
                }
                let overflow = max(0, items.count - 3) + max(0, homeTasks.count - 2)
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(minHeight: 96, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.surfaceHover : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isToday ? Theme.accent.opacity(0.5) : Theme.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showDetail, arrowEdge: .bottom) { detail }
    }

    private func entryRow(color: Color, text: String, done: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10.5))
                .strikethrough(done)
                .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CalendarView.monthTitleFormat.string(from: date).components(separatedBy: " ").first.map { "\($0) \(dayNumber)" } ?? iso)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Button {
                        state.toggleCalItem(item)
                    } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(item.done ? Self.color(item.color) : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Circle().fill(Self.color(item.color)).frame(width: 7, height: 7)
                    Text(item.text)
                        .font(.system(size: 12))
                        .strikethrough(item.done)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        state.removeCalItem(item)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(homeTasks) { task in
                HStack(spacing: 8) {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(task.textWithoutDayTag) · from HOME.md")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(CalendarDoc.colors, id: \.self) { name in
                    Button {
                        newColor = name
                    } label: {
                        Circle()
                            .fill(Self.color(name))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(.white.opacity(newColor == name ? 0.9 : 0), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
            TextField("Add for this day, hit return", text: $newText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(width: 300)
                .onSubmit {
                    state.addCalItem(newText, date: iso, color: newColor)
                    newText = ""
                }
        }
        .padding(14)
        .presentationBackground(.thinMaterial)
    }
}
