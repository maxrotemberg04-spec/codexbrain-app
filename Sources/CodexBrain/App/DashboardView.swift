import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header.rise(0, appeared)
                if let home = state.home {
                    NorthStarHero(board: home).rise(1, appeared)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            TaskCard(title: "Today", marker: "TODAY", tasks: home.today)
                            if state.teamNote != nil {
                                TeamCard()
                            }
                            Planner()
                            ProjectsCard()
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 16) {
                            BriefingCard()
                            GitHubCard()
                            InboxCard()
                            SubscriptionsCard()
                        }
                        .frame(width: 336)
                    }
                    .rise(2, appeared)
                } else if !state.isScanning {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No HOME.md found")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Point CodexBrain at a vault with a HOME note to light up the North Star and task lists.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                        Button("Add Folder") { state.addFolder() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .rise(1, appeared)
                }
                if !state.notes.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        browseSections.frame(maxWidth: .infinity)
                        RecentsCard().frame(width: 336)
                    }
                    .rise(4, appeared)
                }
            }
            .padding(26)
            .frame(maxWidth: 1220, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.bg)
        .navigationTitle("")
        .toolbar { DashboardToolbar() }
        .onAppear { appeared = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Self.dateLine()) · \(Self.greeting())")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                Text("GET SHIT DONE")
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    if state.isScanning { ProgressView().controlSize(.mini) }
                    Text(state.statusLine)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("\(touchedToday) touched today")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var touchedToday: Int {
        state.notes.filter { Calendar.current.isDateInToday($0.modified) }.count
    }

    @State private var showAllFolders = false

    /// View-level curation only: pinned folders up front, machinery behind "More".
    private var browseSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(showAllFolders ? "Pinned only" : "More") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showAllFolders.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.accent)
            }
            ForEach(state.roots) { root in
                let folders = state.topFolders(of: root).filter { showAllFolders || state.isPinned($0.name) }
                if !folders.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(root.name)
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 10)], spacing: 10) {
                            ForEach(folders, id: \.name) { folder in
                                FolderCard(root: root, folder: folder.name, count: folder.count)
                                    .contextMenu {
                                        Button(state.isPinned(folder.name) ? "Unpin from dashboard" : "Pin to dashboard") {
                                            state.togglePin(folder.name)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    static func dateLine() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMMM d"
        return f.string(from: Date())
    }

    static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName().components(separatedBy: " ").first ?? "there"
        switch hour {
        case 5..<12: return "Good morning, \(name)"
        case 12..<18: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }
}

struct DashboardToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            UpdateButton()
            GraphButton()
            AskButton()
            CaptureButton()
        }
    }
}

struct AskButton: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Button {
            state.openCommandBar()
        } label: {
            Label("Ask", systemImage: "sparkle.magnifyingglass")
        }
        .help("Ask your brain anything (⌘K)")
    }
}

struct UpdateButton: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if state.hasGitRepo {
            Button {
                state.updateFromGitHub()
            } label: {
                if state.updating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(state.updating)
            .help("Pull the latest CodexBrain from GitHub and rebuild")
        }
    }
}

struct GraphButton: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Button {
            state.selection = .graph
        } label: {
            Label("Graph", systemImage: "circle.hexagongrid")
        }
        .help("See the whole brain as a graph")
    }
}

struct CaptureButton: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Button {
            state.openCommandBar(seed: "capture ")
        } label: {
            Label("Capture", systemImage: "plus")
        }
        .help("Quick capture (⌘N)")
    }
}

/// The signature element: the North Star as a hero, on a quiet amber wash.
struct NorthStarHero: View {
    let board: HomeBoard

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 9) {
                Text("North Star")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                Text(board.northStar)
                    .font(.system(size: 23, weight: .medium, design: .serif))
                    .italic()
                    .lineSpacing(5)
                    .foregroundStyle(Theme.textPrimary)
                if !board.northStarSub.isEmpty {
                    Text(board.northStarSub)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.surface)
                RadialGradient(colors: [Theme.accent.opacity(0.13), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 460)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct TaskCard: View {
    @EnvironmentObject var state: AppState
    let title: String
    let marker: String
    let tasks: [TaskLine]
    @State private var newTask = ""

    private var done: Int { tasks.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !tasks.isEmpty {
                    Text("\(done)/\(tasks.count)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                    ZStack {
                        Circle().stroke(Theme.stroke, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: tasks.isEmpty ? 0 : CGFloat(done) / CGFloat(tasks.count))
                            .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                }
            }
            if tasks.isEmpty {
                Text("Nothing here. Plan it in HOME.md and it shows up live.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(tasks) { task in
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        state.toggle(task)
                    } label: {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(task.done ? Theme.accent : Theme.textSecondary)
                            .symbolEffect(.bounce, value: Theme.reduceMotion ? false : task.done)
                    }
                    .buttonStyle(.plain)
                    .help(task.done ? "Mark open in HOME.md" : "Mark done in HOME.md")
                    Text(Self.display(task.text))
                        .font(.system(size: 13))
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? Theme.textSecondary : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(marker == "TODAY" ? "Move to This Week" : "Move to Today") {
                        state.moveTask(task, to: marker == "TODAY" ? "THIS WEEK" : "TODAY")
                    }
                    if let home = state.homeNote {
                        Button("Open HOME.md") { state.open(home) }
                    }
                    Button("Delete Task", role: .destructive) { state.removeTask(task) }
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Add a task, hits HOME.md instantly", text: $newTask)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        state.addTask(newTask, toSection: marker)
                        newTask = ""
                    }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    static func display(_ text: String) -> String {
        text.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "**", with: "")
    }
}

struct InboxCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.accentSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(state.openInboxCount)")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text("open inbox items")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let inbox = state.inboxNote {
                Button("Open") { state.open(inbox) }
                    .controlSize(.small)
            }
        }
        .card(padding: 14)
    }
}

/// Founder switchboard: every doc in a *Projects* folder, most recently touched first.
struct ProjectsCard: View {
    @EnvironmentObject var state: AppState
    static let relative = RelativeDateTimeFormatter()

    private var projects: [Note] {
        state.notes
            .filter { $0.topFolder.localizedCaseInsensitiveContains("project") }
            .sorted { $0.modified > $1.modified }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Projects")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(projects.count)")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
            }
            if projects.isEmpty {
                Text("Notes in 03-Projects show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(projects.prefix(4)) { note in
                ProjectRow(note: note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

struct ProjectRow: View {
    @EnvironmentObject var state: AppState
    let note: Note
    @State private var hovering = false

    var body: some View {
        Button {
            state.open(note)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hammer")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.accentSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(note.rootName) · \(ProjectsCard.relative.localizedString(for: note.modified, relativeTo: Date()))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(hovering ? Theme.surfaceHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct RecentsCard: View {
    @EnvironmentObject var state: AppState
    static let relative = RelativeDateTimeFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Recent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(state.notes.sorted(by: { $0.modified > $1.modified }).prefix(8)) { note in
                Button {
                    state.open(note)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text("\(note.folder.isEmpty ? note.rootName : note.folder) · \(Self.relative.localizedString(for: note.modified, relativeTo: Date()))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

// MARK: - Services (dashboard links + key presence; live metrics are a named upgrade)

struct ServiceLink: Identifiable {
    let name: String
    let envVars: [String]
    let dashboard: URL
    var id: String { name }

    static let defaultStack: [ServiceLink] = [
        ServiceLink(name: "Stripe", envVars: ["STRIPE_SECRET_KEY", "STRIPE_API_KEY"],
                    dashboard: URL(string: "https://dashboard.stripe.com")!),
        ServiceLink(name: "Supabase", envVars: ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"],
                    dashboard: URL(string: "https://supabase.com/dashboard")!),
        ServiceLink(name: "RevenueCat", envVars: ["REVENUECAT_API_KEY", "REVENUECAT_SECRET_KEY"],
                    dashboard: URL(string: "https://app.revenuecat.com")!),
    ]

    static func configuredKeys() -> Set<String> {
        var keys = Set(ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty }.keys)
        if let text = try? String(contentsOf: BrainConfig.envFile, encoding: .utf8) {
            for line in text.components(separatedBy: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2, !parts[1].trimmingCharacters(in: .whitespaces).isEmpty {
                    keys.insert(String(parts[0]).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return keys
    }
}

struct ServicesCard: View {
    let configured = ServiceLink.configuredKeys()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Services")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            ForEach(ServiceLink.defaultStack) { service in
                let present = service.envVars.contains { configured.contains($0) }
                HStack(spacing: 9) {
                    Circle()
                        .strokeBorder(present ? Color.clear : Theme.textSecondary, lineWidth: 1)
                        .background(Circle().fill(present ? Theme.accent : Color.clear))
                        .frame(width: 7, height: 7)
                    Text(service.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(present ? "key found" : service.envVars[0])
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Link(destination: service.dashboard) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                    .help("Open \(service.name) dashboard")
                }
            }
            Text("Keys read from ~/.codexbrain/env. Live metrics come next.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

struct FolderCard: View {
    @EnvironmentObject var state: AppState
    let root: VaultRoot
    let folder: String
    let count: Int
    @State private var hovering = false

    var body: some View {
        Button {
            state.selection = .folder(root.id, folder)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: Self.icon(for: folder))
                        .font(.system(size: 13))
                        .foregroundStyle(hovering ? Theme.accent : Theme.textSecondary)
                    Spacer()
                    Text("\(count)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(folder)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(hovering ? Theme.surfaceHover : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    static func icon(for folder: String) -> String {
        let lower = folder.lowercased()
        if lower.contains("inbox") { return "tray" }
        if lower.contains("project") { return "hammer" }
        if lower.contains("career") { return "briefcase" }
        if lower.contains("journal") || lower.contains("memory") { return "book.closed" }
        if lower.contains("learn") { return "graduationcap" }
        if lower.contains("archive") { return "archivebox" }
        if lower.contains("template") { return "square.on.square" }
        if lower.contains("skill") { return "wand.and.rays" }
        if lower.contains("report") { return "chart.bar.doc.horizontal" }
        return "folder"
    }
}
