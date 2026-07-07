import Foundation

struct VaultRoot: Identifiable, Hashable {
    let url: URL
    var name: String { url.lastPathComponent }
    var id: String { url.standardizedFileURL.path }
}

struct Note: Identifiable, Hashable {
    let url: URL
    let rootID: String
    let rootName: String
    let relativePath: String   // e.g. "03-Projects/Race Coach.md"
    let title: String          // filename without extension
    let folder: String         // directory part of relativePath, "" at root
    let modified: Date
    let content: String        // "" when file was too large to cache
    let description: String    // first meaningful line, for the index
    let headings: String       // all headings, lowercased, for retrieval scoring
    let links: [String]        // [[wikilink]] targets, for the graph view

    var id: String { url.standardizedFileURL.path }
    var topFolder: String { folder.components(separatedBy: "/").first ?? "" }

    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id && lhs.modified == rhs.modified }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TaskLine: Identifiable, Hashable {
    let raw: String            // exact line in the file, used to toggle it
    let text: String
    let done: Bool
    var id: String { raw }
}

/// The parsed 🏠 HOME.md hub note: north star + actionable lists.
struct HomeBoard {
    let url: URL
    let northStar: String
    let northStarSub: String   // the line after the star (the method / the clock)
    let today: [TaskLine]
    let week: [TaskLine]

    static func parse(_ note: Note) -> HomeBoard? {
        guard !note.content.isEmpty else { return nil }
        var starLines: [String] = []
        var today: [TaskLine] = []
        var week: [TaskLine] = []
        var section = ""
        for line in note.content.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                section = line.uppercased()
                continue
            }
            if section.contains("NORTH STAR"), starLines.count < 2 {
                let stripped = line
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { starLines.append(stripped) }
            }
            if let task = TaskLine.from(line) {
                if section.contains("TODAY") { today.append(task) }
                else if section.contains("THIS WEEK") { week.append(task) }
            }
        }
        if starLines.isEmpty && today.isEmpty && week.isEmpty { return nil }
        return HomeBoard(url: note.url, northStar: starLines.first ?? "",
                         northStarSub: starLines.count > 1 ? starLines[1] : "",
                         today: today, week: week)
    }

    /// Append a new open task at the end of a section ("TODAY" / "THIS WEEK") in HOME.md.
    static func addTask(_ text: String, sectionMarker: String, in url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var lines = content.components(separatedBy: "\n")
        guard let headIdx = lines.firstIndex(where: {
            $0.hasPrefix("## ") && $0.uppercased().contains(sectionMarker.uppercased())
        }) else { return false }
        var insertAt = headIdx + 1
        var i = headIdx + 1
        while i < lines.count, !lines[i].hasPrefix("## ") {
            if TaskLine.from(lines[i]) != nil { insertAt = i + 1 }
            i += 1
        }
        lines.insert("- [ ] \(text)", at: insertAt)
        return (try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    /// Remove a task line from the file entirely.
    static func removeTask(_ task: TaskLine, in url: URL) -> Bool {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var lines = content.components(separatedBy: "\n")
        guard let idx = lines.firstIndex(of: task.raw) else { return false }
        lines.remove(at: idx)
        return (try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    /// Flip a task's checkbox in the file on disk. Returns true on success.
    static func toggle(_ task: TaskLine, in url: URL) -> Bool {
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let flipped = task.done
            ? task.raw.replacingOccurrences(of: "- [x]", with: "- [ ]")
            : task.raw.replacingOccurrences(of: "- [ ]", with: "- [x]")
        guard let range = text.range(of: task.raw) else { return false }
        text.replaceSubrange(range, with: flipped)
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}

extension TaskLine {
    static func from(_ line: String) -> TaskLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let done: Bool
        if trimmed.hasPrefix("- [ ]") { done = false }
        else if trimmed.lowercased().hasPrefix("- [x]") { done = true }
        else { return nil }
        let text = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return TaskLine(raw: line, text: text, done: done)
    }
}

/// Shared config for the app and the CLI (same defaults suite so roots stay in sync).
enum BrainConfig {
    static let suiteName = "com.maxrotemberg.codexbrain"
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// CODEXBRAIN_ROOT overrides where the index, calendar, and configs live —
    /// for demos, CI, and non-standard installs.
    static var codexBrainRoot: URL {
        if let override = ProcessInfo.processInfo.environment["CODEXBRAIN_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home.appendingPathComponent("Documents/CodexBrain")
    }

    static var defaultRoots: [URL] {
        [home.appendingPathComponent("Documents/FOCUS"), codexBrainRoot]
    }

    /// CODEXBRAIN_ROOTS (colon-separated paths) overrides the browsed roots entirely.
    static func rootURLs() -> [URL] {
        if let override = ProcessInfo.processInfo.environment["CODEXBRAIN_ROOTS"], !override.isEmpty {
            return override.components(separatedBy: ":")
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        let stored = defaults.stringArray(forKey: "roots") ?? []
        let urls = stored.isEmpty ? defaultRoots : stored.map { URL(fileURLWithPath: $0) }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func addRoot(_ url: URL) {
        var stored = defaults.stringArray(forKey: "roots") ?? rootURLs().map(\.path)
        let path = url.standardizedFileURL.path
        guard !stored.contains(path) else { return }
        stored.append(path)
        defaults.set(stored, forKey: "roots")
    }

    static var indexFile: URL { codexBrainRoot.appendingPathComponent("BRAIN-INDEX.md") }
    static var envFile: URL { home.appendingPathComponent(".codexbrain/env") }
}
