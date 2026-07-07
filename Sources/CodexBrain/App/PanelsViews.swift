import SwiftUI

/// "What's going on": renders the newest agent-written daily brief, or a computed
/// digest of file activity when no fresh brief exists.
struct BriefingCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Briefing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(state.brief?.fresh == true ? "fresh" : "digest")
                    .font(Theme.monoSmall)
                    .foregroundStyle(state.brief?.fresh == true ? Theme.accent : Theme.textSecondary)
            }
            if let brief = state.brief, brief.fresh {
                ForEach(Array(brief.lines.prefix(4).enumerated()), id: \.offset) { _, line in
                    briefRow(line)
                }
            } else {
                ForEach(Array(digest.enumerated()), id: \.offset) { _, line in
                    briefRow(line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func briefRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Theme.accent).frame(width: 4, height: 4).padding(.top, 6)
            Text(line)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Deterministic fallback computed from the files themselves.
    private var digest: [String] {
        var lines: [String] = []
        let touched = state.notes.filter { Calendar.current.isDateInToday($0.modified) }
        lines.append("\(touched.count) notes touched today across \(Set(touched.map(\.rootName)).count) root(s).")
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let hot = Dictionary(grouping: state.notes.filter { $0.modified > weekAgo && !$0.topFolder.isEmpty }, by: \.topFolder)
            .max { $0.value.count < $1.value.count }
        if let hot { lines.append("Hottest folder this week: \(hot.key) (\(hot.value.count) notes).") }
        lines.append("Inbox: \(state.openInboxCount) open item(s).")
        if let next = state.home?.today.first(where: { !$0.done }) {
            lines.append("Next up today: \(TaskCard.display(next.text))")
        }
        return lines
    }
}

/// The shared lane: TEAM-TASKS.md from the team repo root. Both founders see and
/// edit the same file; git (auto-pull) keeps the two Macs honest.
struct TeamCard: View {
    @EnvironmentObject var state: AppState
    @State private var newTask = ""

    var body: some View {
        let tasks = state.teamTasks
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Team")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(tasks.filter(\.done).count)/\(tasks.count) · shared via git")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(tasks) { task in
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        state.toggleTeamTask(task)
                    } label: {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(task.done ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Text(TaskCard.display(task.text))
                        .font(.system(size: 13))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? Theme.textSecondary : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Delete Task", role: .destructive) { state.removeTeamTask(task) }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Add a team task, both of you see it", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        state.addTeamTask(newTask)
                        newTask = ""
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// What's shipping: recent commits and PRs from the GitHub REMOTE (via gh CLI),
/// so it reflects pushed truth — never this machine's local branch state.
struct GitHubCard: View {
    @EnvironmentObject var state: AppState
    static let relative = RelativeDateTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Shipping")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("github remote")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            if state.github.isEmpty {
                Text(AppState.ghPath == nil
                     ? "Install the gh CLI to see pushed commits and PRs here."
                     : "No pushed activity yet today. Ship something.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(state.github.prefix(6)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.kind == "pr" ? "arrow.triangle.branch" : "smallcircle.filled.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(item.repo) · \(Self.relative.localizedString(for: item.date, relativeTo: Date()))")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// The AI stack, priced. Reads and edits configs/subscriptions.md in place.
struct SubscriptionsCard: View {
    @EnvironmentObject var state: AppState

    private var total: Double { state.subscriptions.reduce(0) { $0 + $1.priceMonthly } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("AI stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: "$%.0f/mo", total))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 2)
            ForEach(state.subscriptions) { sub in
                SubscriptionRow(sub: sub)
            }
            Text("configs/subscriptions.md · click a price to edit")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

struct SubscriptionRow: View {
    @EnvironmentObject var state: AppState
    let sub: Subscription
    @State private var hovering = false
    @State private var editing = false
    @State private var priceText = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(sub.name)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .help(sub.note)
            Spacer()
            if editing {
                TextField("", text: $priceText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .onSubmit {
                        state.setPrice(sub, to: Double(priceText.filter { "0123456789.".contains($0) }) ?? sub.priceMonthly)
                        editing = false
                    }
            } else {
                Button {
                    priceText = String(format: "%.0f", sub.priceMonthly)
                    editing = true
                } label: {
                    Text(sub.priceMonthly > 0 ? String(format: "$%.0f", sub.priceMonthly) : "$?")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(sub.priceMonthly > 0 ? Theme.textSecondary : Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Click to edit the price")
            }
            Button {
                state.removeSubscription(sub)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("Remove \(sub.name)")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// The week as a to-do planner, driven entirely by HOME.md's THIS WEEK section:
/// day-tagged tasks ("- [ ] Wed: thing") land in their column, untagged ones sit
/// in the Anytime lane. + on a day adds a tagged task. No calendar feeds, no noise.
struct Planner: View {
    @EnvironmentObject var state: AppState
    @State private var anytimeTask = ""

    struct Day: Identifiable {
        let name: String   // Mon
        let label: String  // Mon 6
        let isToday: Bool
        var id: String { name }
    }

    static let labelFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d"; return f
    }()
    static let nameFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()

    private var days: [Day] {
        (0..<7).compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { return nil }
            return Day(name: Self.nameFormat.string(from: date),
                       label: Self.labelFormat.string(from: date),
                       isToday: offset == 0)
        }
    }

    private var anytime: [TaskLine] { (state.home?.week ?? []).filter { $0.dayTag == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Planner")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("THIS WEEK in HOME.md · tag a day or leave it anytime")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                    PlannerColumn(day: day, tasks: tasks(for: day))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    if i < days.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Anytime this week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(anytime) { task in
                    PlannerTaskRow(task: task, showTagMenu: true)
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("Add a week task (right-click it later to schedule a day)", text: $anytimeTask)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            state.addTask(anytimeTask, toSection: "THIS WEEK")
                            anytimeTask = ""
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tasks(for day: Day) -> [TaskLine] {
        (state.home?.week ?? []).filter { $0.dayTag == day.name }
    }
}

struct PlannerColumn: View {
    @EnvironmentObject var state: AppState
    let day: Planner.Day
    let tasks: [TaskLine]
    @State private var adding = false
    @State private var newTask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                if day.isToday {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                }
                Text(day.label)
                    .font(.system(size: 10.5, weight: day.isToday ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(day.isToday ? Theme.accent : Theme.textSecondary)
                Spacer(minLength: 0)
                Button {
                    adding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Add a task for \(day.label)")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    TextField("Task for \(day.name)", text: $newTask)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(width: 260)
                        .padding(12)
                        .presentationBackground(.thinMaterial)
                        .onSubmit {
                            state.addTask("\(day.name): \(newTask)", toSection: "THIS WEEK")
                            newTask = ""
                            adding = false
                        }
                }
            }
            if tasks.isEmpty {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
            ForEach(tasks) { task in
                PlannerTaskRow(task: task, showTagMenu: false)
            }
        }
    }
}

struct PlannerTaskRow: View {
    @EnvironmentObject var state: AppState
    let task: TaskLine
    let showTagMenu: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                state.toggle(task)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(task.done ? Theme.accent : Theme.textSecondary)
                    .symbolEffect(.bounce, value: Theme.reduceMotion ? false : task.done)
            }
            .buttonStyle(.plain)
            Text(TaskCard.display(task.textWithoutDayTag))
                .font(.system(size: 11))
                .strikethrough(task.done)
                .foregroundStyle(task.done ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if showTagMenu {
                Menu("Schedule on") {
                    ForEach(TaskLine.dayNames, id: \.self) { day in
                        Button(day) { state.retagTask(task, day: day) }
                    }
                }
            } else {
                Button("Unschedule (anytime)") { state.retagTask(task, day: nil) }
            }
            Button("Move to Today") { state.moveTask(task, to: "TODAY") }
            Button("Delete Task", role: .destructive) { state.removeTask(task) }
        }
    }
}
