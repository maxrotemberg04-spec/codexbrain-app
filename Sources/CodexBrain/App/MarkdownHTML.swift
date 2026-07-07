import Foundation

/// Small markdown -> themed HTML converter for the reading pane.
/// Covers what the vault actually uses: headings, lists, tasks, fences, quotes,
/// tables, links, wiki-links, images (inlined as data URIs so WKWebView can show them).
/// ponytail: not CommonMark-complete; extend when a real note renders wrong.
enum MarkdownHTML {
    static func page(for note: Note) -> String {
        page(markdown: note.content, noteURL: note.url, title: note.title)
    }

    static func page(markdown: String, noteURL: URL, title: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>\(css)</style></head>
        <body>\(body(from: markdown, noteURL: noteURL))</body></html>
        """
    }

    // MARK: - Block-level parsing

    static func body(from markdown: String, noteURL: URL) -> String {
        var lines = markdown.components(separatedBy: "\n")
        // YAML frontmatter is metadata, not prose: hide it like Obsidian does.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }
        var html = ""
        var inFence = false
        var listKind: String? = nil
        var para: [String] = []
        var quote: [String] = []
        var table: [String] = []

        func closeList() { if let kind = listKind { html += "</\(kind)>\n"; listKind = nil } }
        func flushPara() {
            guard !para.isEmpty else { return }
            html += "<p>" + para.map { inline($0, noteURL: noteURL) }.joined(separator: "<br>") + "</p>\n"
            para = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            var quoteLines = quote
            // Obsidian callout: "> [!tip] Title" renders as a styled card, not a plain quote.
            var calloutTitle: String? = nil
            if let first = quoteLines.first, first.hasPrefix("[!"), let close = first.range(of: "]") {
                let type = String(first[first.index(first.startIndex, offsetBy: 2)..<close.lowerBound])
                let title = String(first[close.upperBound...]).trimmingCharacters(in: .whitespaces)
                calloutTitle = title.isEmpty ? type.capitalized : title
                quoteLines.removeFirst()
            }
            let inner = quoteLines.map { inline($0, noteURL: noteURL) }.joined(separator: "<br>")
            if let title = calloutTitle {
                html += "<div class=\"callout\"><div class=\"callout-title\">✦ \(escape(title))</div>"
                    + (inner.isEmpty ? "" : "<p>\(inner)</p>") + "</div>\n"
            } else {
                html += "<blockquote><p>\(inner)</p></blockquote>\n"
            }
            quote = []
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            html += "<table>\n"
            var isHeader = true
            for row in table {
                let cells = row.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let isSeparator = cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } && !$0.isEmpty }
                if isSeparator { isHeader = false; continue }
                let tag = isHeader ? "th" : "td"
                html += "<tr>" + cells.map { "<\(tag)>\(inline($0, noteURL: noteURL))</\(tag)>" }.joined() + "</tr>\n"
                if isHeader { isHeader = false }
            }
            html += "</table>\n"
            table = []
        }
        func flushAll() { flushPara(); flushQuote(); flushTable(); closeList() }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if inFence {
                if trimmed.hasPrefix("```") { html += "</code></pre>\n"; inFence = false }
                else { html += escape(rawLine) + "\n" }
                continue
            }
            if trimmed.hasPrefix("```") {
                flushAll()
                html += "<pre><code>"
                inFence = true
                continue
            }
            if trimmed.isEmpty { flushAll(); continue }

            if trimmed.hasPrefix("#") {
                flushAll()
                let level = min(trimmed.prefix(while: { $0 == "#" }).count, 6)
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                html += "<h\(level)>\(inline(text, noteURL: noteURL))</h\(level)>\n"
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAll(); html += "<hr>\n"; continue
            }
            if trimmed.hasPrefix(">") {
                flushPara(); flushTable(); closeList()
                quote.append(trimmed.drop(while: { $0 == ">" || $0 == " " }).description)
                continue
            }
            if trimmed.hasPrefix("|") && trimmed.contains("|") {
                flushPara(); flushQuote(); closeList()
                table.append(trimmed)
                continue
            }
            if let item = listItem(trimmed) {
                flushPara(); flushQuote(); flushTable()
                if listKind != item.kind { closeList(); html += "<\(item.kind)>\n"; listKind = item.kind }
                if let done = item.task {
                    html += "<li class=\"task\"><input type=\"checkbox\" disabled\(done ? " checked" : "")>"
                        + inline(item.text, noteURL: noteURL) + "</li>\n"
                } else {
                    html += "<li>" + inline(item.text, noteURL: noteURL) + "</li>\n"
                }
                continue
            }
            flushQuote(); flushTable(); closeList()
            para.append(trimmed)
        }
        if inFence { html += "</code></pre>\n" }
        flushAll()
        return html
    }

    static func listItem(_ line: String) -> (kind: String, text: String, task: Bool?)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[ ]") { return ("ul", String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces), false) }
            if text.lowercased().hasPrefix("[x]") { return ("ul", String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces), true) }
            return ("ul", text, nil)
        }
        let digits = line.prefix(while: { $0.isNumber })
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return ("ol", String(line.dropFirst(digits.count + 2)), nil)
        }
        return nil
    }

    // MARK: - Inline parsing

    static func inline(_ text: String, noteURL: URL) -> String {
        var out = escape(text)

        // Protect code spans from the formatting passes below.
        var codeSpans: [String] = []
        out = transform(out, pattern: "`([^`]+)`") { groups in
            codeSpans.append("<code>\(groups[1] ?? "")</code>")
            return "\u{1}\(codeSpans.count - 1)\u{1}"
        }
        out = transform(out, pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") { groups in
            imageTag(alt: groups[1] ?? "", src: groups[2] ?? "", noteURL: noteURL)
        }
        out = transform(out, pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") { groups in
            "<a href=\"\(groups[2] ?? "")\">\(groups[1] ?? "")</a>"
        }
        out = transform(out, pattern: "\\[\\[([^\\]|]+)(\\|([^\\]]+))?\\]\\]") { groups in
            let target = (groups[1] ?? "").trimmingCharacters(in: .whitespaces)
            let label = groups[3] ?? target
            let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            return "<a class=\"wiki\" href=\"codex://wiki/\(encoded)\">\(label)</a>"
        }
        out = replace(out, pattern: "\\*\\*([^*]+)\\*\\*", template: "<strong>$1</strong>")
        out = replace(out, pattern: "(?<![\\w*])\\*([^*]+)\\*(?![\\w*])", template: "<em>$1</em>")
        out = replace(out, pattern: "~~([^~]+)~~", template: "<del>$1</del>")
        out = replace(out, pattern: "==([^=]+)==", template: "<mark>$1</mark>")
        out = replace(out, pattern: "(^|[\\s(])#([A-Za-z][\\w/-]*)", template: "$1<span class=\"tag\">#$2</span>")

        for (i, span) in codeSpans.enumerated() {
            out = out.replacingOccurrences(of: "\u{1}\(i)\u{1}", with: span)
        }
        return out
    }

    static func imageTag(alt: String, src: String, noteURL: URL) -> String {
        if src.hasPrefix("http") { return "<img src=\"\(src)\" alt=\"\(alt)\">" }
        // Local image: inline as data URI (loadHTMLString has no file access).
        let decoded = src.removingPercentEncoding ?? src
        let fileURL = URL(fileURLWithPath: decoded, relativeTo: noteURL.deletingLastPathComponent())
        guard let data = try? Data(contentsOf: fileURL), data.count < 4_000_000 else {
            return "<span class=\"missing\">[image: \(alt.isEmpty ? decoded : alt)]</span>"
        }
        let mime: String
        switch fileURL.pathExtension.lowercased() {
        case "png": mime = "image/png"
        case "gif": mime = "image/gif"
        case "svg": mime = "image/svg+xml"
        case "webp": mime = "image/webp"
        default: mime = "image/jpeg"
        }
        return "<img src=\"data:\(mime);base64,\(data.base64EncodedString())\" alt=\"\(alt)\">"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// NSRegularExpression with a $n template. Boring and reliable.
    static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Regex replacement with a Swift closure over the capture groups.
    static func transform(_ text: String, pattern: String, _ builder: ([String?]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            var groups: [String?] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            result += builder(groups)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: - Reading-pane styles (mirrors Theme tokens)

    static let css = """
    :root { color-scheme: light dark;
      --bg:#F6F5F1; --fg:#201F1D; --muted:#736F68; --surface:#FFFFFF;
      --stroke:rgba(0,0,0,.09); --accent:#A9761F; --accent-soft:rgba(169,118,31,.35);
      --accent-tint:rgba(169,118,31,.07); --mark:rgba(169,118,31,.22); }
    @media (prefers-color-scheme: dark) { :root {
      --bg:#0F1013; --fg:#ECEAE4; --muted:#8E939B; --surface:#17181C;
      --stroke:rgba(255,255,255,.08); --accent:#E8A94E; --accent-soft:rgba(232,169,78,.4);
      --accent-tint:rgba(232,169,78,.07); --mark:rgba(232,169,78,.26); } }
    * { box-sizing: border-box; }
    body { font: 15.5px/1.7 -apple-system, system-ui, sans-serif; letter-spacing:.01em;
      background: var(--bg); color: var(--fg); margin: 0 auto; max-width: 46em;
      padding: 34px 46px 100px; }
    h1,h2,h3,h4,h5,h6 { letter-spacing: -.017em; line-height: 1.22; margin: 1.6em 0 .5em; font-weight: 680; }
    h1 { font-size: 2.05em; margin-top:.35em; padding-bottom:.4em; border-bottom:1px solid var(--stroke); }
    h2 { font-size: 1.45em; } h3 { font-size: 1.16em; } h4,h5,h6 { font-size: 1em; }
    p, ul, ol, blockquote, table, pre { margin: 0 0 .95em; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    a.wiki { border-bottom: 1px dashed var(--accent-soft); }
    code { font: 13px ui-monospace, SFMono-Regular, monospace; background: var(--surface);
      border: 1px solid var(--stroke); border-radius: 5px; padding: 1.5px 5.5px; }
    pre { background: var(--surface); border: 1px solid var(--stroke); border-radius: 10px;
      padding: 15px 17px; overflow-x: auto; }
    pre code { border: 0; background: none; padding: 0; font-size: 12.8px; line-height: 1.58; }
    blockquote { border-left: 3px solid var(--accent-soft); padding: 2px 0 2px 17px; color: var(--muted); }
    .callout { background: var(--accent-tint); border: 1px solid var(--stroke);
      border-left: 3px solid var(--accent); border-radius: 8px; padding: 12px 16px; }
    .callout-title { font-weight: 650; color: var(--accent); font-size: .92em; margin-bottom: 4px; }
    .callout p { margin: 0; }
    mark { background: var(--mark); color: inherit; border-radius: 3px; padding: 0 2px; }
    .tag { font: 11px ui-monospace, monospace; color: var(--accent); background: var(--accent-tint);
      border: 1px solid var(--stroke); border-radius: 999px; padding: 1px 8px; white-space: nowrap; }
    ul, ol { padding-left: 1.5em; }
    li { margin: .2em 0; }
    li.task { list-style: none; margin-left: -1.5em; }
    input[type=checkbox] { accent-color: var(--accent); margin-right: 8px; vertical-align: -1.5px; }
    table { border-collapse: collapse; width: 100%; font-size: 13.5px; }
    th, td { border: 1px solid var(--stroke); padding: 6.5px 11px; text-align: left; vertical-align: top; }
    th { color: var(--muted); font-weight: 600; }
    img { max-width: 100%; border-radius: 9px; }
    hr { border: 0; border-top: 1px solid var(--stroke); margin: 2.1em 0; }
    .missing { color: var(--muted); font-style: italic; }
    ::selection { background: var(--accent-soft); }
    """
}
