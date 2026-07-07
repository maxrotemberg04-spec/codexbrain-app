import Foundation

enum VaultScanner {
    /// Directories never worth indexing. Hidden dirs (.obsidian, .git) are skipped by the enumerator.
    static let skipDirs: Set<String> = [
        "node_modules", ".build", ".swiftpm", "_skill-library", "reference", "DerivedData",
        "gbrain-reference",
    ]
    /// Generated files that would make the brain index itself, plus repo
    /// housekeeping docs that are code-project files, not notes.
    static let skipFiles: Set<String> = ["BRAIN-INDEX.md", "CONTRIBUTING.md", "LICENSE"]
    static let maxCachedBytes = 1_000_000

    static func scan(roots: [URL]) -> [Note] {
        var notes: [Note] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for rootURL in roots {
            let root = VaultRoot(url: rootURL)
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                // Symlinks (vault/ -> FOCUS, builds/ -> Learn) would double-index or wander off; skip them.
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values?.isDirectory == true {
                    if skipDirs.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    continue
                }
                guard url.pathExtension.lowercased() == "md",
                      !skipFiles.contains(url.lastPathComponent) else { continue }
                let path = url.standardizedFileURL.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let size = values?.fileSize ?? 0
                let content: String = size <= maxCachedBytes
                    ? ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                    : ""
                let relative = String(path.dropFirst(root.url.standardizedFileURL.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let folder = relative.contains("/")
                    ? relative.components(separatedBy: "/").dropLast().joined(separator: "/")
                    : ""
                notes.append(Note(
                    url: url,
                    rootID: root.id,
                    rootName: root.name,
                    relativePath: relative,
                    title: url.deletingPathExtension().lastPathComponent,
                    folder: folder,
                    modified: values?.contentModificationDate ?? .distantPast,
                    content: content,
                    description: describe(content),
                    headings: headings(of: content),
                    links: wikiLinks(of: content)
                ))
            }
        }
        return notes
    }

    static func wikiLinks(of content: String) -> [String] {
        var links: [String] = []
        var search = content.startIndex..<content.endIndex
        while let open = content.range(of: "[[", range: search) {
            guard let close = content.range(of: "]]", range: open.upperBound..<content.endIndex) else { break }
            let inner = String(content[open.upperBound..<close.lowerBound])
            if let target = inner.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespaces),
               !target.isEmpty, target.count < 120 {
                links.append(target)
            }
            search = close.upperBound..<content.endIndex
        }
        return links
    }

    /// Cheapest possible change detector: newest .md modification across roots, no content reads.
    static func newestModification(roots: [URL]) -> Date {
        var newest = Date.distantPast
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values?.isDirectory == true {
                    if skipDirs.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    continue
                }
                guard url.pathExtension.lowercased() == "md", !skipFiles.contains(url.lastPathComponent) else { continue }
                if let d = values?.contentModificationDate, d > newest { newest = d }
            }
        }
        return newest
    }

    static func headings(of content: String) -> String {
        content.components(separatedBy: "\n")
            .filter { $0.hasPrefix("#") }
            .map { $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased() }
            .joined(separator: " · ")
    }

    /// First meaningful line of a note, trimmed for the one-line index entry.
    static func describe(_ content: String) -> String {
        var inFrontmatter = false
        for (i, line) in content.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if i == 0 && trimmed == "---" { inFrontmatter = true; continue }
            if inFrontmatter { if trimmed == "---" { inFrontmatter = false }; continue }
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), trimmed != "---" else { continue }
            let cleaned = trimmed
                .replacingOccurrences(of: ">", with: "")
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }
            return String(cleaned.prefix(110))
        }
        return ""
    }
}
