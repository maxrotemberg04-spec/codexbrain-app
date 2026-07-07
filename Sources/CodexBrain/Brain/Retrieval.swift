import Foundation

/// Deterministic retrieval (no model calls): keywords -> score every note from
/// metadata -> open the single best note -> extract the single best section ->
/// follow one [[wikilink]] pointer if that section is weak. Answers cite sources.
enum Retrieval {
    struct Answer {
        let note: Note
        let heading: String
        let body: String
        let followedFrom: Note?
        let alternates: [Note]
        let elapsedMS: Double
    }

    static let stopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "am", "do", "does", "did",
        "what", "whats", "when", "where", "who", "why", "how", "which", "my", "me", "i", "we",
        "you", "your", "our", "it", "its", "of", "in", "on", "at", "to", "for", "with", "and",
        "or", "not", "no", "this", "that", "these", "those", "about", "from", "up", "so", "if",
        "can", "could", "should", "would", "will", "have", "has", "had", "there", "here", "get",
    ]

    static func keywords(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    /// Occurrences of `term` in `text` at word boundaries only, so "star" never
    /// matches "startup". Both arguments must already be lowercased.
    static func wordHits(_ term: String, in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: term, range: search) {
            let beforeOK = r.lowerBound == text.startIndex
                || !isWordChar(text[text.index(before: r.lowerBound)])
            let afterOK = r.upperBound == text.endIndex || !isWordChar(text[r.upperBound])
            if beforeOK && afterOK { count += 1 }
            search = r.upperBound..<text.endIndex
        }
        return count
    }

    static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    static func score(_ note: Note, terms: [String]) -> Int {
        guard !terms.isEmpty else { return 0 }
        let title = note.title.lowercased()
        let folder = note.folder.lowercased()
        let desc = note.description.lowercased()
        let content = note.content.lowercased()
        var total = 0
        for term in terms {
            var s = 0
            if wordHits(term, in: title) > 0 { s += 6 }
            else if term.count >= 5, title.contains(term) { s += 3 }   // stem-ish partials only
            if wordHits(term, in: folder) > 0 { s += 2 }
            if wordHits(term, in: desc) > 0 { s += 3 }
            if wordHits(term, in: note.headings) > 0 { s += 4 }
            if !content.isEmpty { s += min(wordHits(term, in: content), 3) }
            total += s
        }
        if total > 0, note.modified.timeIntervalSinceNow > -7 * 86_400 { total += 1 }
        return total
    }

    /// Split a note into (heading, body) blocks and return the best-scoring one.
    static func bestSection(of content: String, terms: [String]) -> (heading: String, body: String, score: Int) {
        var blocks: [(heading: String, lines: [String])] = [("(top)", [])]
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append((heading.isEmpty ? "(section)" : heading, []))
            } else {
                blocks[blocks.count - 1].lines.append(line)
            }
        }
        var best: (heading: String, body: String, score: Int) = ("(top)", "", -1)
        for block in blocks {
            let body = block.lines.joined(separator: "\n")
            let lowerHeading = block.heading.lowercased()
            let lowerBody = body.lowercased()
            var s = 0
            for term in terms {
                if wordHits(term, in: lowerHeading) > 0 { s += 5 }
                s += min(wordHits(term, in: lowerBody), 3)
            }
            if s > best.score, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || s > 0 {
                best = (block.heading, body, s)
            }
        }
        let trimmedLines = best.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        let capped = trimmedLines.prefix(50).joined(separator: "\n")
        return (best.heading, String(capped.prefix(2200)), max(best.score, 0))
    }

    static func firstWikiLink(in text: String) -> String? {
        guard let open = text.range(of: "[["),
              let close = text.range(of: "]]", range: open.upperBound..<text.endIndex) else { return nil }
        let inner = String(text[open.upperBound..<close.lowerBound])
        return inner.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespaces)
    }

    static func resolve(title: String, in notes: [Note]) -> Note? {
        let target = title.lowercased()
        return notes.first { $0.title.lowercased() == target }
            ?? notes.first { $0.title.lowercased().contains(target) }
    }

    static func rank(_ query: String, notes: [Note]) -> [Note] {
        let terms = keywords(query)
        guard !terms.isEmpty else { return notes }
        return notes
            .map { ($0, score($0, terms: terms)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    static func ask(_ query: String, notes: [Note]) -> Answer? {
        let start = DispatchTime.now()
        let terms = keywords(query)
        guard !terms.isEmpty else { return nil }
        let ranked = rank(query, notes: notes)
        guard let top = ranked.first else { return nil }

        var section = bestSection(of: top.content, terms: terms)
        var note = top
        var followedFrom: Note? = nil
        // Weak section that points elsewhere: follow the pointer once (and only once).
        if section.score <= terms.count,
           let linkTitle = firstWikiLink(in: section.body),
           let linked = resolve(title: linkTitle, in: notes), linked.id != top.id {
            let linkedSection = bestSection(of: linked.content, terms: terms)
            if linkedSection.score > section.score {
                followedFrom = top
                note = linked
                section = linkedSection
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        return Answer(
            note: note,
            heading: section.heading,
            body: section.body,
            followedFrom: followedFrom,
            alternates: Array(ranked.dropFirst().prefix(3)),
            elapsedMS: elapsed
        )
    }
}
