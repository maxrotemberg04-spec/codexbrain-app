import SwiftUI

/// The signature: ⌘K drops a floating glass bar over everything. One field does
/// it all — notes rank as you type, verbs become actions (add / capture / go),
/// and a real question gets answered from the vault with its source, instantly,
/// no model calls. Raycast for your second brain.
enum CommandBarEngine {
    enum Intent: Equatable {
        case add(String)
        case capture(String)
        case goto(String)
        case none
    }

    static let navTargets = ["dashboard", "calendar", "graph"]

    static func classify(_ raw: String, folders: [String] = []) -> Intent {
        let q = raw.trimmingCharacters(in: .whitespaces)
        let lower = q.lowercased()
        guard !lower.isEmpty else { return .none }
        for prefix in ["add ", "todo "] where lower.hasPrefix(prefix) {
            let payload = String(q.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !payload.isEmpty { return .add(payload) }
        }
        for prefix in ["capture ", "note "] where lower.hasPrefix(prefix) {
            let payload = String(q.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !payload.isEmpty { return .capture(payload) }
        }
        if lower.count >= 3, let target = navTargets.first(where: { $0.hasPrefix(lower) }) {
            return .goto(target)
        }
        if let folder = folders.first(where: { $0.lowercased() == lower }) {
            return .goto(folder)
        }
        return .none
    }

    /// A query that reads like a question gets the retrieval answer inline.
    static func wantsAnswer(_ q: String) -> Bool {
        q.hasSuffix("?") || Retrieval.keywords(q).count >= 3
    }
}

struct CommandBarOverlay: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { state.showCommandBar = false }
            CommandBarPanel()
                .padding(.top, 110)
        }
    }
}

struct CommandBarPanel: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    enum Row: Identifiable {
        case addToday(String)
        case addWeek(String)
        case capture(String)
        case goto(SidebarItem, String, String)      // destination, label, icon
        case answer(Retrieval.Answer)
        case note(Note)

        var id: String {
            switch self {
            case .addToday(let t): return "add-today-\(t)"
            case .addWeek(let t): return "add-week-\(t)"
            case .capture(let t): return "capture-\(t)"
            case .goto(_, let label, _): return "goto-\(label)"
            case .answer(let a): return "answer-\(a.note.id)"
            case .note(let n): return "note-\(n.id)"
            }
        }
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [Row] = []
        let folders = state.roots.flatMap { state.topFolders(of: $0).map(\.name) }
        switch CommandBarEngine.classify(q, folders: folders) {
        case .add(let payload):
            out.append(.addToday(payload))
            out.append(.addWeek(payload))
            return out
        case .capture(let payload):
            out.append(.capture(payload))
            return out
        case .goto(let target):
            out.append(gotoRow(for: target))
        case .none:
            break
        }
        if case .none = CommandBarEngine.classify(q, folders: folders), CommandBarEngine.wantsAnswer(q),
           let answer = Retrieval.ask(q, notes: state.notes) {
            out.append(.answer(answer))
        }
        for note in Retrieval.rank(q, notes: state.notes).prefix(6) {
            if case .some = out.first(where: { if case .answer(let a) = $0 { return a.note.id == note.id } else { return false } }) { continue }
            out.append(.note(note))
        }
        if !q.isEmpty { out.append(.capture(q)) }   // last resort: anything can become an inbox item
        return out
    }

    private func gotoRow(for target: String) -> Row {
        switch target {
        case "dashboard": return .goto(.dashboard, "Go to Dashboard", "sparkle")
        case "calendar": return .goto(.calendar, "Go to Calendar", "calendar")
        case "graph": return .goto(.graph, "Go to Graph", "circle.hexagongrid")
        default:
            if let root = state.roots.first(where: { r in state.topFolders(of: r).contains { $0.name == target } }) {
                return .goto(.folder(root.id, target), "Go to \(target)", FolderCard.icon(for: target))
            }
            return .goto(.dashboard, "Go to Dashboard", "sparkle")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                TextField("Search notes, ask a question, or add / capture…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { execute(at: selected) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                Text("esc")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceHover.opacity(0.6)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            let currentRows = rows
            if !currentRows.isEmpty {
                Divider().opacity(0.4)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(currentRows.enumerated()), id: \.element.id) { i, row in
                            rowView(row, isSelected: i == selected)
                                .onTapGesture { execute(at: i) }
                                .onHover { if $0 { selected = i } }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 640)
        .glassBackground(radius: 16)
        .onAppear {
            query = state.commandSeed
            state.commandSeed = ""
            focused = true
        }
        .onExitCommand { state.showCommandBar = false }
        .onChange(of: query) { selected = 0 }
    }

    private func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    private func execute(at index: Int) {
        let currentRows = rows
        guard currentRows.indices.contains(index) else { return }
        switch currentRows[index] {
        case .addToday(let text):
            state.addTask(text, toSection: "TODAY")
        case .addWeek(let text):
            state.addTask(text, toSection: "THIS WEEK")
        case .capture(let text):
            state.capture(title: "", text: text)
        case .goto(let destination, _, _):
            state.selection = destination
        case .answer(let answer):
            state.open(answer.note)
        case .note(let note):
            state.open(note)
        }
        state.showCommandBar = false
    }

    @ViewBuilder
    private func rowView(_ row: Row, isSelected: Bool) -> some View {
        Group {
            switch row {
            case .addToday(let text):
                actionRow(icon: "plus.circle.fill", label: "Add to Today", detail: text, isSelected: isSelected)
            case .addWeek(let text):
                actionRow(icon: "calendar.badge.plus", label: "Add to This Week", detail: text, isSelected: isSelected)
            case .capture(let text):
                actionRow(icon: "tray.and.arrow.down", label: "Capture to inbox", detail: text, isSelected: isSelected)
            case .goto(_, let label, let icon):
                actionRow(icon: icon, label: label, detail: nil, isSelected: isSelected)
            case .answer(let answer):
                answerRow(answer, isSelected: isSelected)
            case .note(let note):
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(note.rootName)/\(note.folder.isEmpty ? "" : note.folder)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Text("↩")
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Theme.accentSoft : .clear))
        .contentShape(Rectangle())
    }

    private func actionRow(icon: String, label: String, detail: String?, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            if let detail {
                Text("“\(detail)”")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isSelected {
                Text("↩")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func answerRow(_ answer: Retrieval.Answer, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("\(answer.note.title) § \(answer.heading)")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.1f ms", answer.elapsedMS))
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(TaskCard.display(answer.body)
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(4)
            Text("↩ open the source note")
                .font(Theme.monoSmall)
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft.opacity(0.5)))
    }
}
