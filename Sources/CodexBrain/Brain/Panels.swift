import Foundation

/// File-backed dashboard panels: subscriptions, the synced calendar week, and the
/// agent-written brief. Files are the only state; the app just renders and edits them.

struct Subscription: Identifiable, Hashable {
    let name: String
    let priceMonthly: Double
    let note: String
    let raw: String
    var id: String { raw }
}

enum Subscriptions {
    static var file: URL { BrainConfig.codexBrainRoot.appendingPathComponent("configs/subscriptions.md") }

    /// Lines look like: `- Name | $200/mo | note`
    static func parse(_ text: String) -> [Subscription] {
        text.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("- ") else { return nil }
            let parts = line.dropFirst(2).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { return nil }
            let digits = parts[1].filter { "0123456789.".contains($0) }
            return Subscription(
                name: parts[0],
                priceMonthly: Double(digits) ?? 0,
                note: parts.count > 2 ? parts[2] : "",
                raw: line
            )
        }
    }

    static func load() -> [Subscription] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func setPrice(_ sub: Subscription, to price: Double, in url: URL) -> Bool {
        rewriteLine(sub, in: url) { _ in
            let shown = price == price.rounded() ? String(format: "$%.0f/mo", price) : String(format: "$%.2f/mo", price)
            return "- \(sub.name) | \(shown)\(sub.note.isEmpty ? "" : " | \(sub.note)")"
        }
    }

    static func remove(_ sub: Subscription, in url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var lines = text.components(separatedBy: "\n")
        guard let idx = lines.firstIndex(of: sub.raw) else { return false }
        lines.remove(at: idx)
        return (try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    private static func rewriteLine(_ sub: Subscription, in url: URL, _ make: (String) -> String) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        var lines = text.components(separatedBy: "\n")
        guard let idx = lines.firstIndex(of: sub.raw) else { return false }
        lines[idx] = make(sub.raw)
        return (try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}

struct Brief: Equatable {
    let title: String
    let lines: [String]
    let fresh: Bool
    let url: URL
}

enum BriefFile {
    static var reportsDir: URL { BrainConfig.codexBrainRoot.appendingPathComponent("reports") }

    /// Newest daily-brief*.md; fresh means written in the last 36 hours.
    static func load() -> Brief? {
        let fm = FileManager.default
        let candidates = ((try? fm.contentsOfDirectory(at: reportsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.lowercased().hasPrefix("daily-brief") && $0.pathExtension == "md" }
        let newest = candidates.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a < b
        }
        guard let newest, let text = try? String(contentsOf: newest, encoding: .utf8) else { return nil }
        let modified = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        var title = "Briefing"
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("# ") { title = String(line.dropFirst(2)) }
            if line.hasPrefix("- ") { lines.append(String(line.dropFirst(2))) }
        }
        guard !lines.isEmpty else { return nil }
        return Brief(title: title, lines: lines, fresh: modified.timeIntervalSinceNow > -36 * 3600, url: newest)
    }
}

/// Shared team lane: any note titled TEAM-TASKS (typically its own tiny git repo
/// added as a root). Every checkbox line in it is a team task; both founders'
/// dashboards read and write the same file and sync via git.
enum TeamTasks {
    static func parse(_ content: String) -> [TaskLine] {
        content.components(separatedBy: "\n").compactMap(TaskLine.from)
    }

    static func add(_ text: String, to url: URL) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let updated = content.hasSuffix("\n") ? content + "- [ ] \(clean)\n" : content + "\n- [ ] \(clean)\n"
        return (try? updated.write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}

/// Recent GitHub activity parsed from the events API (fetched via the gh CLI, so
/// it reads the REMOTE — never local branch state).
struct GHItem: Identifiable, Equatable {
    let repo: String
    let title: String
    let kind: String   // "commit" | "pr"
    let date: Date
    var id: String { "\(repo)-\(kind)-\(title)-\(date.timeIntervalSince1970)" }
}

enum GitHubFeed {
    static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    static func parse(_ data: Data) -> [GHItem] {
        guard let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var items: [GHItem] = []
        for event in events {
            guard let type = event["type"] as? String,
                  let repoDict = event["repo"] as? [String: Any],
                  let fullRepo = repoDict["name"] as? String,
                  let createdAt = event["created_at"] as? String,
                  let date = iso.date(from: createdAt) else { continue }
            let repo = fullRepo.components(separatedBy: "/").last ?? fullRepo
            let payload = event["payload"] as? [String: Any] ?? [:]
            switch type {
            case "PushEvent":
                let commits = payload["commits"] as? [[String: Any]] ?? []
                if let last = commits.last, let message = last["message"] as? String {
                    let firstLine = message.components(separatedBy: "\n").first ?? message
                    let extra = commits.count > 1 ? " (+\(commits.count - 1))" : ""
                    items.append(GHItem(repo: repo, title: firstLine + extra, kind: "commit", date: date))
                }
            case "PullRequestEvent":
                if let pr = payload["pull_request"] as? [String: Any], let title = pr["title"] as? String {
                    let action = payload["action"] as? String ?? "updated"
                    items.append(GHItem(repo: repo, title: "PR \(action): \(title)", kind: "pr", date: date))
                }
            default:
                continue
            }
        }
        return items
    }
}

/// Dated, color-coded items for the month calendar. One markdown file, one line
/// per item: `- [ ] 2026-07-12 @teal The thing`. Syncs with the CodexBrain repo,
/// so both Macs (and agents) share the same calendar.
struct CalItem: Identifiable, Hashable {
    let task: TaskLine          // raw checkbox line (toggle/remove reuse HomeBoard)
    let date: String            // yyyy-MM-dd
    let color: String           // palette name, default "amber"
    let text: String
    var id: String { task.raw }
    var done: Bool { task.done }
}

enum CalendarDoc {
    static var file: URL { BrainConfig.codexBrainRoot.appendingPathComponent("CALENDAR.md") }
    static let colors = ["amber", "teal", "blue", "rose", "sage", "lavender"]
    static let iso: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func parse(_ content: String) -> [CalItem] {
        content.components(separatedBy: "\n").compactMap { line in
            guard let task = TaskLine.from(line) else { return nil }
            var parts = task.text.components(separatedBy: " ").filter { !$0.isEmpty }
            guard let first = parts.first, first.count == 10,
                  first[first.index(first.startIndex, offsetBy: 4)] == "-" else { return nil }
            let date = first
            parts.removeFirst()
            var color = "amber"
            if let tag = parts.first, tag.hasPrefix("@") {
                let name = String(tag.dropFirst()).lowercased()
                if colors.contains(name) { color = name; parts.removeFirst() }
            }
            return CalItem(task: task, date: date, color: color, text: parts.joined(separator: " "))
        }
    }

    static func load() -> [CalItem] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func add(_ text: String, date: String, color: String, to url: URL) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return false }
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? "# Calendar\n"
        let line = "- [ ] \(date) @\(color) \(clean)"
        let updated = content.hasSuffix("\n") ? content + line + "\n" : content + "\n" + line + "\n"
        return (try? updated.write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}

extension TaskLine {
    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// "Wed: ship the thing" -> "Wed". Tasks without a tag belong to the whole week.
    var dayTag: String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let prefix = String(text[..<colon]).trimmingCharacters(in: .whitespaces).capitalized
        return Self.dayNames.contains(prefix) ? prefix : nil
    }

    var textWithoutDayTag: String {
        guard dayTag != nil, let colon = text.firstIndex(of: ":") else { return text }
        return String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
}
