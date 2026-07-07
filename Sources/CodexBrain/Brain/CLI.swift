import Foundation

/// Terminal face of the brain, for Max and his agent fleet. No model calls anywhere.
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        switch args.first {
        case "ask":
            return ask(args.dropFirst().joined(separator: " "))
        case "remember":
            return remember(args.dropFirst().joined(separator: " "))
        case "reindex":
            return reindex()
        case "selfcheck", "--selfcheck":
            return SelfCheck.run()
        default:
            print("""
            codexbrain — Max's second brain (deterministic, no model calls)

              codexbrain ask "question"       best-matching note section + its source
              codexbrain remember "fact"      append to the vault inbox + refresh the index
              codexbrain reindex              rebuild BRAIN-INDEX.md from disk
              codexbrain selfcheck            run built-in assertions

            No arguments launches the desktop app.
            """)
            return args.isEmpty || args.first == "help" || args.first == "--help" ? 0 : 1
        }
    }

    /// The PDF ladder, verbatim: keywords -> score every catalog entry WITHOUT opening
    /// files -> open only the winner -> best section -> one pointer follow. Deep content
    /// scan happens only when the index has no hit at all.
    static func ask(_ query: String) -> Int32 {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("usage: codexbrain ask \"question\""); return 1
        }
        let start = DispatchTime.now()
        let terms = Retrieval.keywords(query)
        guard !terms.isEmpty else { print("Question is all stopwords; add a real keyword."); return 1 }

        var entries = Catalog.load(BrainConfig.indexFile)
        if entries.isEmpty {
            _ = reindex()
            entries = Catalog.load(BrainConfig.indexFile)
        }
        let ranked = entries
            .map { ($0, Retrieval.score($0, terms: terms)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        var filesOpened = 0
        func read(_ url: URL) -> String {
            filesOpened += 1
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        let mode: String
        var chosen: Note
        var section: (heading: String, body: String, score: Int)
        var via: String? = nil
        var alternates: [String]

        if let top = ranked.first?.0 {
            mode = "index"
            chosen = top
            section = Retrieval.bestSection(of: read(top.url), terms: terms)
            if section.score <= terms.count,
               let linkTitle = Retrieval.firstWikiLink(in: section.body),
               let linked = Retrieval.resolve(title: linkTitle, in: entries), linked.id != top.id {
                let linkedSection = Retrieval.bestSection(of: read(linked.url), terms: terms)
                if linkedSection.score > section.score {
                    via = top.title
                    chosen = linked
                    section = linkedSection
                }
            }
            alternates = ranked.dropFirst().prefix(3).map(\.0.title)
        } else {
            mode = "deep scan"   // nothing in the index matched; fall back to full contents
            let notes = VaultScanner.scan(roots: BrainConfig.rootURLs())
            filesOpened = notes.count
            guard let answer = Retrieval.ask(query, notes: notes) else {
                print("No match in \(notes.count) notes. Try different words, or `codexbrain reindex`.")
                return 1
            }
            chosen = answer.note
            section = (answer.heading, answer.body, 1)
            via = answer.followedFrom?.title
            alternates = answer.alternates.map(\.title)
        }

        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        print(section.body.isEmpty ? "(section is empty — see source)" : section.body)
        print("")
        print("source: \(chosen.url.path) § \(section.heading)")
        if let via { print("via:    \(via) (followed one [[wikilink]] pointer)") }
        if !alternates.isEmpty { print("also:   \(alternates.joined(separator: " · "))") }
        print(String(format: "%.1fms · %d entries scored · %d file(s) opened · %@ path",
                     ms, entries.count, filesOpened, mode))
        return 0
    }

    @discardableResult
    static func remember(_ text: String, vaultRoot: URL? = nil) -> Int32 {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("usage: codexbrain remember \"the fact to keep\""); return 1
        }
        let roots = vaultRoot.map { [$0] } ?? BrainConfig.rootURLs()
        guard let inbox = inboxFile(in: roots) else {
            print("No vault root found to write into."); return 1
        }
        let day = BrainIndex.dayFormat.string(from: Date())
        let entry = "- [ ] \(day): \(text)\n"
        if let handle = try? FileHandle(forWritingTo: inbox) {
            handle.seekToEndOfFile()
            handle.write(("\n" + entry).data(using: .utf8)!)
            try? handle.close()
        } else {
            try? entry.write(to: inbox, atomically: true, encoding: .utf8)
        }
        if vaultRoot == nil {
            let notes = VaultScanner.scan(roots: BrainConfig.rootURLs())
            BrainIndex.write(notes: notes, to: BrainConfig.indexFile)
            print("Remembered in \(inbox.path) and reindexed \(notes.count) notes.")
        } else {
            print("Remembered in \(inbox.path).")   // fixture mode: never touch the real index
        }
        return 0
    }

    /// The vault's inbox note: prefer an existing "*Inbox*" file inside 00-Inbox, create one if missing.
    static func inboxFile(in roots: [URL]) -> URL? {
        let fm = FileManager.default
        for root in roots {
            let inboxDir = root.appendingPathComponent("00-Inbox")
            guard fm.fileExists(atPath: inboxDir.path) else { continue }
            let existing = (try? fm.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "md" && $0.lastPathComponent.localizedCaseInsensitiveContains("inbox") }
                .sorted { $0.lastPathComponent.count > $1.lastPathComponent.count }
            if let found = existing?.first { return found }
            let created = inboxDir.appendingPathComponent("Inbox.md")
            try? "# Inbox\n".write(to: created, atomically: true, encoding: .utf8)
            return created
        }
        return nil
    }

    static func reindex() -> Int32 {
        let start = DispatchTime.now()
        let notes = VaultScanner.scan(roots: BrainConfig.rootURLs())
        let ok = BrainIndex.write(notes: notes, to: BrainConfig.indexFile)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        print(ok
            ? String(format: "Indexed %d notes -> %@ (%.0fms)", notes.count, BrainConfig.indexFile.path, ms)
            : "Failed to write \(BrainConfig.indexFile.path)")
        return ok ? 0 : 1
    }
}

/// Reads BRAIN-INDEX.md back into scoreable entries so `ask` never has to open
/// note files just to rank them. Entries are Notes with empty content.
enum Catalog {
    static func load(_ file: URL) -> [Note] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var entries: [Note] = []
        var root = ""
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { root = String(line.dropFirst(3)); continue }
            guard line.hasPrefix("- ["),
                  let titleEnd = line.range(of: "]("),
                  let pathEnd = line.range(of: ")", range: titleEnd.upperBound..<line.endIndex)
            else { continue }
            let title = String(line[line.index(line.startIndex, offsetBy: 3)..<titleEnd.lowerBound])
            let path = String(line[titleEnd.upperBound..<pathEnd.lowerBound])
            var rest = String(line[pathEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
            var folder = ""
            if rest.hasSuffix(")"), let metaStart = rest.range(of: "(", options: .backwards) {
                let meta = String(rest[metaStart.upperBound...].dropLast())
                folder = meta.components(separatedBy: " · ").first ?? ""
                if folder == "root" { folder = "" }
                rest = String(rest[..<metaStart.lowerBound])
            }
            let desc = rest.hasPrefix("—") ? String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
                                           : rest.trimmingCharacters(in: .whitespaces)
            let url = URL(fileURLWithPath: path)
            entries.append(Note(
                url: url, rootID: root, rootName: root,
                relativePath: path, title: title, folder: folder,
                modified: .distantPast, content: "", description: desc, headings: "", links: []
            ))
        }
        return entries
    }
}

/// The one runnable check: a fixture vault in tmp, asserted end to end.
enum SelfCheck {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        if condition { print("  ok  \(label)") }
        else { print("  FAIL \(label)"); failures += 1 }
    }

    static func run() -> Int32 {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("codexbrain-selfcheck-\(UUID().uuidString)")
        let vault = base.appendingPathComponent("FOCUS")
        defer { try? fm.removeItem(at: base) }

        func write(_ rel: String, _ text: String) {
            let url = vault.appendingPathComponent(rel)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }

        write("🏠 HOME.md", """
        # 🏠 FOCUS

        ## ⭐ NORTH STAR
        > ### Become a technical generalist who ships.

        ## ✅ TODAY
        - [ ] Ship repo #1
        - [x] Resume export

        ## 🗓 THIS WEEK
        - [ ] Finish eval-harness v1
        """)
        write("00-Inbox/✍️ Inbox.md", "# Inbox\n")
        write("03-Projects/Race Coach.md", """
        # Race Coach

        ## Race date picker
        The wheel picker builds clean and saves the race date to Supabase.

        ## Safety layer
        Deterministic guardrails run before the model sees anything.
        """)
        write("99-Reference/Training Notes.md", """
        # Training Notes

        ## Weekly volume
        annual plan details live in [[Race Coach]] under the safety layer.
        """)
        write("99-Reference/startup-market-dynamics.md", """
        # startup-market-dynamics

        Startup markets and startup dynamics, startup startup startup.
        """)

        print("selfcheck: fixture at \(vault.path)")
        let notes = VaultScanner.scan(roots: [vault])
        check(notes.count == 5, "scanner found 5 notes (got \(notes.count))")

        let home = notes.first { $0.title.contains("HOME") }.flatMap(HomeBoard.parse)
        check(home?.northStar.contains("technical generalist") == true, "HOME north star parsed")
        check(home?.today.count == 2 && home?.today[1].done == true, "HOME today tasks parsed with state")
        check(home?.week.count == 1, "HOME this-week tasks parsed")

        let start = DispatchTime.now()
        let answer = Retrieval.ask("race date wheel picker", notes: notes)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        check(answer?.note.title == "Race Coach", "ask found the right note (got \(answer?.note.title ?? "nil"))")
        check(answer?.heading == "Race date picker", "ask found the right section (got \(answer?.heading ?? "nil"))")

        let followed = Retrieval.ask("annual plan", notes: notes)
        check(followed != nil, "pointer query answered")

        // Regression: "star" must not match "startup" (word-boundary scoring).
        let northStar = Retrieval.ask("north star", notes: notes)
        check(northStar?.note.title.contains("HOME") == true,
              "word boundaries: north star -> HOME, not startup (got \(northStar?.note.title ?? "nil"))")

        let indexFile = base.appendingPathComponent("BRAIN-INDEX.md")
        BrainIndex.write(notes: notes, to: indexFile)
        let entries = Catalog.load(indexFile)
        check(entries.count == notes.count, "catalog round-trip count (got \(entries.count))")
        check(entries.contains { $0.title == "Race Coach" && $0.folder == "03-Projects" },
              "catalog round-trip title + folder")

        _ = CLI.remember("selfcheck fact", vaultRoot: vault)
        let inbox = (try? String(contentsOf: vault.appendingPathComponent("00-Inbox/✍️ Inbox.md"), encoding: .utf8)) ?? ""
        check(inbox.contains("selfcheck fact"), "remember appended to the inbox")

        let html = MarkdownHTML.body(from: "# Head\n**bold** `code` [[Race Coach]]\n- [ ] task\n```swift\nlet x = 1\n```", noteURL: vault)
        check(html.contains("<h1>"), "markdown: heading")
        check(html.contains("<strong>bold</strong>"), "markdown: bold")
        check(html.contains("<code>code</code>"), "markdown: inline code")
        check(html.contains("codex://wiki/"), "markdown: wikilink -> codex:// URL")
        check(html.contains("checkbox"), "markdown: task checkbox")
        check(html.contains("<pre>"), "markdown: code fence")

        let training = notes.first { $0.title == "Training Notes" }
        check(training?.links.contains("Race Coach") == true, "wikilink extraction for the graph")

        let homeURL = vault.appendingPathComponent("🏠 HOME.md")
        check(HomeBoard.addTask("Selfcheck task", sectionMarker: "TODAY", in: homeURL), "addTask wrote HOME.md")
        var reparsed = VaultScanner.scan(roots: [vault]).first { $0.title.contains("HOME") }.flatMap(HomeBoard.parse)
        check(reparsed?.today.count == 3 && reparsed?.today.last?.text == "Selfcheck task", "addTask appended to TODAY")
        if let added = reparsed?.today.last {
            check(HomeBoard.removeTask(added, in: homeURL), "removeTask wrote HOME.md")
            reparsed = VaultScanner.scan(roots: [vault]).first { $0.title.contains("HOME") }.flatMap(HomeBoard.parse)
            check(reparsed?.today.count == 2, "removeTask deleted the line")
        }

        let noFM = MarkdownHTML.body(from: "---\ntitle: secret\ntags: [a]\n---\n# Visible", noteURL: vault)
        check(!noFM.contains("secret") && noFM.contains("<h1>Visible</h1>"), "markdown: frontmatter hidden")

        let subs = Subscriptions.parse("- A | $10/mo | x\n- B | $5.50/mo |\nnot a sub")
        check(subs.count == 2 && subs[0].priceMonthly == 10 && subs[1].priceMonthly == 5.5, "subscriptions parse")

        check(CommandBarEngine.classify("add ship the fix") == .add("ship the fix"), "command bar: add intent")
        check(CommandBarEngine.classify("capture cool idea") == .capture("cool idea"), "command bar: capture intent")
        check(CommandBarEngine.classify("cal") == .goto("calendar"), "command bar: nav intent")
        check(CommandBarEngine.classify("random words") == .none, "command bar: plain search")
        check(CommandBarEngine.wantsAnswer("what did i decide about pricing?")
              && !CommandBarEngine.wantsAnswer("redis"), "command bar: answer trigger")

        let calDoc = "# Calendar\n- [ ] 2026-07-14 @teal Redis clone\n- [x] 2026-07-12 Weekly review\n- [ ] no date line\n"
        let calItems = CalendarDoc.parse(calDoc)
        check(calItems.count == 2 && calItems[0].color == "teal" && calItems[0].text == "Redis clone"
              && calItems[1].done && calItems[1].color == "amber", "calendar doc parse")
        let calFile = base.appendingPathComponent("CALENDAR.md")
        try? calDoc.write(to: calFile, atomically: true, encoding: .utf8)
        check(CalendarDoc.add("New thing", date: "2026-07-15", color: "rose", to: calFile), "calendar add")
        let reloaded = CalendarDoc.parse((try? String(contentsOf: calFile, encoding: .utf8)) ?? "")
        check(reloaded.count == 3 && reloaded[2].color == "rose", "calendar add round-trip")

        let ghJSON = #"""
        [{"type":"PushEvent","repo":{"name":"max/kai-ios"},"created_at":"2026-07-06T12:00:00Z",
          "payload":{"commits":[{"message":"Fix coach brain"},{"message":"Add safety layer\ndetails"}]}},
         {"type":"PullRequestEvent","repo":{"name":"max/eval-harness"},"created_at":"2026-07-06T13:00:00Z",
          "payload":{"action":"opened","pull_request":{"title":"Add providers"}}}]
        """#
        let gh = GitHubFeed.parse(Data(ghJSON.utf8))
        check(gh.count == 2 && gh[0].repo == "kai-ios" && gh[0].title.contains("(+1)") && gh[1].kind == "pr",
              "github events parse")

        let teamFile = base.appendingPathComponent("TEAM-TASKS.md")
        try? "# Team\n- [ ] First shared task\n".write(to: teamFile, atomically: true, encoding: .utf8)
        check(TeamTasks.add("Second task", to: teamFile), "team task added")
        let teamContent = (try? String(contentsOf: teamFile, encoding: .utf8)) ?? ""
        check(TeamTasks.parse(teamContent).count == 2, "team tasks parse")

        let tagged = TaskLine(raw: "- [ ] Wed: ship", text: "Wed: ship", done: false)
        check(tagged.dayTag == "Wed" && tagged.textWithoutDayTag == "ship", "day-tag parsing")

        let callout = MarkdownHTML.body(from: "> [!tip] Race day\n> Pace the first 10k.", noteURL: vault)
        check(callout.contains("callout-title") && callout.contains("Race day"), "markdown: obsidian callout")
        let extras = MarkdownHTML.body(from: "a ==big== day #race", noteURL: vault)
        check(extras.contains("<mark>big</mark>") && extras.contains("class=\"tag\""), "markdown: highlight + tag chip")

        if failures == 0 {
            print(String(format: "SELFCHECK OK · retrieval %.1fms on fixture", ms))
            return 0
        }
        print("SELFCHECK FAILED: \(failures) assertion(s)")
        return 1
    }
}
