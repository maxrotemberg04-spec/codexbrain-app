import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case dashboard
    case calendar
    case graph
    case all(String)             // rootID
    case folder(String, String)  // rootID, top-level folder
}

@MainActor
final class AppState: ObservableObject {
    @Published var roots: [VaultRoot] = []
    @Published var notes: [Note] = []
    @Published var home: HomeBoard?
    @Published var selection: SidebarItem? = .dashboard
    @Published var selectedNoteID: String?
    @Published var searchText = ""
    @Published var isScanning = false
    @Published var statusLine = "indexing..."
    @Published var showCommandBar = false
    @Published var showNoteList = true   // ⌘\ hides it for pure reading
    var commandSeed = ""

    func openCommandBar(seed: String = "") {
        commandSeed = seed
        showCommandBar = true
    }
    @Published var subscriptions: [Subscription] = []
    @Published var brief: Brief?
    @Published var updating = false
    @Published var github: [GHItem] = []
    @Published var calItems: [CalItem] = []

    var selectedNote: Note? { notes.first { $0.id == selectedNoteID } }

    var openInboxCount: Int {
        let inboxNotes = notes.filter { $0.folder.hasPrefix("00-Inbox") }
        let openTasks = inboxNotes.reduce(0) { count, note in
            count + note.content.components(separatedBy: "\n").filter {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]")
            }.count
        }
        return max(openTasks, 0)
    }

    var inboxNote: Note? {
        notes.first { $0.folder.hasPrefix("00-Inbox") && $0.title.localizedCaseInsensitiveContains("inbox") }
            ?? notes.first { $0.folder.hasPrefix("00-Inbox") }
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        let rootURLs = BrainConfig.rootURLs()
        Task.detached(priority: .userInitiated) {
            let start = DispatchTime.now()
            let scanned = VaultScanner.scan(roots: rootURLs)
            BrainIndex.write(notes: scanned, to: BrainConfig.indexFile)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            await MainActor.run {
                self.roots = rootURLs.map { VaultRoot(url: $0) }
                self.notes = scanned
                self.home = Self.findHome(in: scanned)
                self.statusLine = String(format: "%d notes indexed · %.0f ms", scanned.count, ms)
                self.isScanning = false
                self.noteScanBaseline()
                self.subscriptions = Subscriptions.load()
                self.brief = BriefFile.load()
                self.calItems = CalendarDoc.load()
            }
        }
    }

    static func findHome(in notes: [Note]) -> HomeBoard? {
        notes
            .filter { $0.folder.isEmpty && $0.title.uppercased().contains("HOME") }
            .compactMap(HomeBoard.parse)
            .max { ($0.today.count + $0.week.count) < ($1.today.count + $1.week.count) }
    }

    func toggle(_ task: TaskLine) {
        guard let home, HomeBoard.toggle(task, in: home.url) else { return }
        rescan()  // ponytail: full rescan on toggle; fast enough at this vault size
    }

    /// Multi-line paste imports one task per line.
    func addTask(_ text: String, toSection marker: String) {
        guard let home else { return }
        let items = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return }
        for item in items {
            _ = HomeBoard.addTask(item, sectionMarker: marker, in: home.url)
        }
        rescan()
    }

    func moveTask(_ task: TaskLine, to marker: String) {
        guard let home,
              HomeBoard.removeTask(task, in: home.url),
              HomeBoard.addTask(task.text, sectionMarker: marker, in: home.url) else { return }
        rescan()
    }

    /// Re-tag a week task onto a day ("Wed: x") or back to anytime (nil).
    func retagTask(_ task: TaskLine, day: String?) {
        guard let home else { return }
        let text = day.map { "\($0): \(task.textWithoutDayTag)" } ?? task.textWithoutDayTag
        guard HomeBoard.removeTask(task, in: home.url),
              HomeBoard.addTask(text, sectionMarker: "THIS WEEK", in: home.url) else { return }
        rescan()
    }

    func setPrice(_ sub: Subscription, to price: Double) {
        guard Subscriptions.setPrice(sub, to: price, in: Subscriptions.file) else { return }
        rescan()
    }

    func removeSubscription(_ sub: Subscription) {
        guard Subscriptions.remove(sub, in: Subscriptions.file) else { return }
        rescan()
    }

    // MARK: - Folder pins (view-level curation; files never move)

    static let defaultPins = ["00-Inbox", "01-Learning", "02-Career", "03-Projects",
                              "context", "automation", "workflow", "use-cases"]

    var pins: [String] {
        BrainConfig.defaults.stringArray(forKey: "pins") ?? Self.defaultPins
    }

    func isPinned(_ folder: String) -> Bool { pins.contains(folder) }

    func togglePin(_ folder: String) {
        var current = pins
        if let idx = current.firstIndex(of: folder) { current.remove(at: idx) } else { current.append(folder) }
        BrainConfig.defaults.set(current, forKey: "pins")
        objectWillChange.send()
    }

    // MARK: - Self-update: pull the repo, rebuild, ask for a relaunch.

    var hasGitRepo: Bool {
        FileManager.default.fileExists(atPath: BrainConfig.codexBrainRoot.appendingPathComponent(".git").path)
    }

    nonisolated static func shell(_ path: String, _ args: [String], cwd: URL) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (1, "\(error)") }
        p.waitUntilExit()
        return (p.terminationStatus, String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    func updateFromGitHub() {
        guard !updating else { return }
        updating = true
        statusLine = "updating from GitHub..."
        Task.detached(priority: .userInitiated) {
            let root = BrainConfig.codexBrainRoot
            let pull = Self.shell("/usr/bin/git", ["pull", "--ff-only"], cwd: root)
            let message: String
            if pull.0 != 0 {
                message = "update failed: git pull (see terminal)"
            } else if pull.1.contains("Already up to date") {
                message = "already on the latest version"
            } else {
                let build = Self.shell("/bin/bash", ["install.sh"], cwd: root.appendingPathComponent("app"))
                message = build.0 == 0 ? "updated — quit and reopen to run it" : "update failed during build"
            }
            await MainActor.run {
                self.updating = false
                self.statusLine = message
            }
        }
    }

    /// Quiet background pull (~5 min cadence) so remote updates — a teammate's push,
    /// Hermes acting on a text, the Mac mini — show up here without anyone clicking.
    /// Only when the working tree is clean; never merges, never rebuilds.
    private func autoPull() {
        guard !updating else { return }
        let codexRoot = BrainConfig.codexBrainRoot.standardizedFileURL
        // Shared roots (team folders with their own git repo): full two-way sync — commit, rebase-pull, push.
        // The CodexBrain playbook repo: pull only; its commits stay 100% Max's.
        var sharedRoots = BrainConfig.rootURLs().filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(".git").path)
                && $0.standardizedFileURL != codexRoot
        }
        _ = sharedRoots.partition { _ in false }   // keep order stable
        let pullOnly = hasGitRepo ? [BrainConfig.codexBrainRoot] : []
        guard !sharedRoots.isEmpty || !pullOnly.isEmpty else { return }
        Task.detached(priority: .background) {
            var changed = false
            for repo in pullOnly {
                let dirty = Self.shell("/usr/bin/git", ["status", "--porcelain"], cwd: repo)
                guard dirty.0 == 0, dirty.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let before = Self.shell("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repo).1
                _ = Self.shell("/usr/bin/git", ["pull", "--ff-only", "--quiet"], cwd: repo)
                if Self.shell("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repo).1 != before { changed = true }
            }
            for repo in sharedRoots {
                let dirty = Self.shell("/usr/bin/git", ["status", "--porcelain"], cwd: repo)
                if dirty.0 == 0, !dirty.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    _ = Self.shell("/usr/bin/git", ["add", "-A"], cwd: repo)
                    _ = Self.shell("/usr/bin/git", ["commit", "-m", "sync", "--quiet"], cwd: repo)
                }
                let before = Self.shell("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repo).1
                let pull = Self.shell("/usr/bin/git", ["pull", "--rebase", "--quiet"], cwd: repo)
                if pull.0 != 0 { _ = Self.shell("/usr/bin/git", ["rebase", "--abort"], cwd: repo) }
                _ = Self.shell("/usr/bin/git", ["push", "--quiet"], cwd: repo)   // silent no-op until a remote exists
                if Self.shell("/usr/bin/git", ["rev-parse", "HEAD"], cwd: repo).1 != before { changed = true }
            }
            if changed {
                await MainActor.run {
                    self.statusLine = "synced shared repos"
                    self.rescan()
                }
            }
        }
    }

    func removeTask(_ task: TaskLine) {
        guard let home, HomeBoard.removeTask(task, in: home.url) else { return }
        rescan()
    }

    var homeNote: Note? {
        guard let home else { return nil }
        return notes.first { $0.url == home.url }
    }

    // MARK: - Team lane (any note titled TEAM-TASKS, usually its own shared repo root)

    var teamNote: Note? {
        notes.first { $0.title.uppercased().contains("TEAM-TASKS") }
    }

    var teamTasks: [TaskLine] {
        teamNote.map { TeamTasks.parse($0.content) } ?? []
    }

    func toggleTeamTask(_ task: TaskLine) {
        guard let note = teamNote, HomeBoard.toggle(task, in: note.url) else { return }
        rescan()
    }

    func addTeamTask(_ text: String) {
        guard let note = teamNote, TeamTasks.add(text, to: note.url) else { return }
        rescan()
    }

    func removeTeamTask(_ task: TaskLine) {
        guard let note = teamNote, HomeBoard.removeTask(task, in: note.url) else { return }
        rescan()
    }

    // MARK: - Calendar items (CALENDAR.md at the CodexBrain root)

    func addCalItem(_ text: String, date: String, color: String) {
        guard CalendarDoc.add(text, date: date, color: color, to: CalendarDoc.file) else { return }
        rescan()
    }

    func toggleCalItem(_ item: CalItem) {
        guard HomeBoard.toggle(item.task, in: CalendarDoc.file) else { return }
        rescan()
    }

    func removeCalItem(_ item: CalItem) {
        guard HomeBoard.removeTask(item.task, in: CalendarDoc.file) else { return }
        rescan()
    }

    // MARK: - Scratchpad (one always-there note, edited from the menu bar)

    var scratchpadURL: URL {
        let inboxDir = BrainConfig.rootURLs()
            .map { $0.appendingPathComponent("00-Inbox") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
            ?? BrainConfig.codexBrainRoot.appendingPathComponent("inbox")
        return inboxDir.appendingPathComponent("Scratchpad.md")
    }

    func loadScratchpad() -> String {
        (try? String(contentsOf: scratchpadURL, encoding: .utf8)) ?? "# Scratchpad\n\n"
    }

    func saveScratchpad(_ text: String) {
        try? text.write(to: scratchpadURL, atomically: true, encoding: .utf8)
    }

    // MARK: - GitHub activity (reads the remote via gh; never local branch state)

    static var ghPath: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    func refreshGitHub() {
        guard let gh = Self.ghPath else { return }
        Task.detached(priority: .background) {
            let login = Self.shell(gh, ["api", "/user", "-q", ".login"], cwd: BrainConfig.home).1
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !login.isEmpty else { return }
            let events = Self.shell(gh, ["api", "/users/\(login)/events?per_page=40"], cwd: BrainConfig.home)
            guard events.0 == 0 else { return }
            let items = GitHubFeed.parse(Data(events.1.utf8))
            await MainActor.run { self.github = items }
        }
    }

    // MARK: - Live refresh: agents edit files / run `codexbrain remember`, the app follows.

    private var watcher: Timer?
    private var lastScanNewest: Date = .distantPast
    private var watchTick = 0

    func startWatching() {
        guard watcher == nil else { return }
        watcher = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.watchTick += 1
                self.refreshIfChanged()
                if self.watchTick % 25 == 0 {   // ~every 5 minutes
                    self.autoPull()
                    self.refreshGitHub()
                }
            }
        }
    }

    func noteScanBaseline() {
        lastScanNewest = notes.map(\.modified).max() ?? .distantPast
    }

    private func refreshIfChanged() {
        guard !isScanning else { return }
        let rootURLs = BrainConfig.rootURLs()
        let baseline = lastScanNewest
        Task.detached(priority: .utility) {
            let newest = VaultScanner.newestModification(roots: rootURLs)   // stat-only, no reads
            await MainActor.run {
                if newest > baseline { self.rescan() }
            }
        }
    }

    func notesFor(_ item: SidebarItem?) -> [Note] {
        let base: [Note]
        switch item {
        case .all(let rootID):
            base = notes.filter { $0.rootID == rootID }
        case .folder(let rootID, let folder):
            base = notes.filter { $0.rootID == rootID && $0.topFolder == folder }
        default:
            base = notes
        }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return base.sorted { $0.modified > $1.modified }
        }
        return Retrieval.rank(searchText, notes: base)
    }

    func topFolders(of root: VaultRoot) -> [(name: String, count: Int)] {
        let inRoot = notes.filter { $0.rootID == root.id && !$0.topFolder.isEmpty }
        let grouped = Dictionary(grouping: inRoot) { $0.topFolder }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.count) }
    }

    func count(for item: SidebarItem) -> Int {
        switch item {
        case .all(let rootID): return notes.filter { $0.rootID == rootID }.count
        case .folder(let rootID, let folder): return notes.filter { $0.rootID == rootID && $0.topFolder == folder }.count
        case .dashboard, .graph, .calendar: return 0
        }
    }

    func open(_ note: Note) {
        selection = note.topFolder.isEmpty ? .all(note.rootID) : .folder(note.rootID, note.topFolder)
        selectedNoteID = note.id
    }

    func openWiki(_ name: String) {
        guard let note = Retrieval.resolve(title: name, in: notes) else { return }
        open(note)
    }

    func save(note: Note, content: String) {
        try? content.write(to: note.url, atomically: true, encoding: .utf8)
        rescan()
    }

    /// Quick capture: a title makes a new note in 00-Inbox; no title appends to the inbox list.
    func capture(title: String, text: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty {
            guard !cleanText.isEmpty else { return }
            CLI.remember(cleanText)
        } else {
            let dir = BrainConfig.rootURLs()
                .map { $0.appendingPathComponent("00-Inbox") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
                ?? BrainConfig.rootURLs().first?.appendingPathComponent("00-Inbox")
            guard let dir else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safe = cleanTitle.replacingOccurrences(of: "/", with: "-")
            let url = dir.appendingPathComponent("\(safe).md")
            let stamp = BrainIndex.dayFormat.string(from: Date())
            try? "# \(cleanTitle)\n\n\(cleanText)\n\n(captured \(stamp))\n".write(to: url, atomically: true, encoding: .utf8)
        }
        rescan()
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add to brain"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        BrainConfig.addRoot(url)
        rescan()
    }
}

struct CodexBrainApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(state)
        }
        .defaultSize(width: 1340, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ask Your Brain") { state.openCommandBar() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Quick Capture") { state.openCommandBar(seed: "capture ") }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Reindex") { state.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(state.showNoteList ? "Hide Note List" : "Show Note List") {
                    state.showNoteList.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(state)
        } label: {
            Image(systemName: "sparkle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Always-on capture: the ✦ in the menu bar takes a thought from ANY app straight
/// to the inbox + index, no context switch.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""
    @State private var scratch = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("CodexBrain")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(state.home?.today.filter { !$0.done }.count ?? 0) open today")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
            }
            TextField("Capture to inbox, hit return", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .onSubmit {
                    let clean = text.trimmingCharacters(in: .whitespaces)
                    guard !clean.isEmpty else { return }
                    state.capture(title: "", text: clean)
                    text = ""
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Scratchpad")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                TextEditor(text: $scratch)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 130)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.stroke))
                    .onChange(of: scratch) {
                        saveTask?.cancel()
                        let snapshot = scratch
                        saveTask = Task {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            guard !Task.isCancelled else { return }
                            state.saveScratchpad(snapshot)
                        }
                    }
            }
            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    state.selection = .dashboard
                }
                .controlSize(.small)
                Spacer()
                Text(state.statusLine)
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { scratch = state.loadScratchpad() }
        .onDisappear {
            saveTask?.cancel()
            state.saveScratchpad(scratch)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
            } detail: {
                Group {
                    switch state.selection {
                    case .all, .folder: BrowseSplit()
                    case .calendar: CalendarView()
                    case .graph: GraphView()
                    default: DashboardView()
                    }
                }
                .id(state.selection)
                .transition(.opacity)
                .animation(Theme.reduceMotion ? nil : .easeOut(duration: 0.16), value: state.selection)
            }
            if state.showCommandBar {
                CommandBarOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .zIndex(1)
            }
        }
        .animation(Theme.reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.9), value: state.showCommandBar)
        .frame(minWidth: 1060, minHeight: 660)
        .background(Theme.bg)
        .tint(Theme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .task { bootstrap() }
    }

    private func bootstrap() {
        if !Bundle.main.bundlePath.hasSuffix(".app") {
            NSApp.setActivationPolicy(.regular)   // dev runs via `swift run` still get a real window
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.applicationIconImage = Theme.dockIcon()
        state.rescan()
        state.startWatching()
        state.refreshGitHub()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in state.rescan() }   // index can never drift: refresh whenever Max comes back
        }
    }
}

