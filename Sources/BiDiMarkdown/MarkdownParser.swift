//
//  MarkdownParser.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import Foundation

enum MarkdownParser {

    static func parse(_ markdown: String, autolinkPlainURLs: Bool = true) -> [MarkdownBlockNode] {
        parseLines(markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n"), autolinkPlainURLs: autolinkPlainURLs)
    }

    private static func parseLines(_ lines: [String], autolinkPlainURLs: Bool) -> [MarkdownBlockNode] {
        var blocks: [MarkdownBlockNode] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            if let fence = fenceMarker(trimmed) {
                var code: [String] = []
                var j = i + 1
                while j < lines.count, !lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                    code.append(lines[j]); j += 1
                }
                blocks.append(.codeBlock(language: fence.language, code: code.joined(separator: "\n")))
                i = j + 1; continue
            }

            if isHorizontalRule(trimmed) { blocks.append(.horizontalRule); i += 1; continue }

            if let (level, content) = atxHeading(trimmed) {
                blocks.append(.heading(level: level, inline: MarkdownInlineScanner.parse(content, autolinkPlainURLs: autolinkPlainURLs)))
                i += 1; continue
            }

            if i + 1 < lines.count, looksLikeTableRow(line), let alignments = tableDelimiter(lines[i + 1]) {
                let header = splitTableRow(line)
                var rows: [[String]] = []
                var j = i + 2
                while j < lines.count, looksLikeTableRow(lines[j]) { rows.append(splitTableRow(lines[j])); j += 1 }
                blocks.append(.table(
                    alignments: alignments,
                    header: header.map { MarkdownInlineScanner.parse($0, autolinkPlainURLs: autolinkPlainURLs) },
                    rows: rows.map { row in row.map { MarkdownInlineScanner.parse($0, autolinkPlainURLs: autolinkPlainURLs) } }
                ))
                i = j; continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                var j = i
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[j].trimmingCharacters(in: .whitespaces)
                    l.removeFirst()
                    if l.hasPrefix(" ") { l.removeFirst() }
                    quoteLines.append(l); j += 1
                }
                blocks.append(.blockQuote(parseLines(quoteLines, autolinkPlainURLs: autolinkPlainURLs)))
                i = j; continue
            }

            if let (alt, url) = standaloneImage(trimmed) { blocks.append(.image(alt: alt, url: url)); i += 1; continue }

            if let marker = listMarker(line) {
                let result = collectList(lines, from: i, markerKind: marker)
                blocks.append(result.ordered
                    ? .orderedList(start: result.start, items: result.items.map { parseLines($0, autolinkPlainURLs: autolinkPlainURLs) }, tight: true)
                    : .unorderedList(items: result.items.map { parseLines($0, autolinkPlainURLs: autolinkPlainURLs) }, checked: result.checked, tight: true))
                i += result.consumed; continue
            }

            var rawLines: [String] = []
            var j = i
            while j < lines.count {
                let raw = lines[j]
                let t = raw.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if fenceMarker(t) != nil || isHorizontalRule(t) || atxHeading(t) != nil
                    || t.hasPrefix(">") || listMarker(raw) != nil { break }
                var cleanedLine = t
                if cleanedLine.hasSuffix("\\") { cleanedLine.removeLast() }
                rawLines.append(cleanedLine)
                j += 1
            }
            // Real "\n" characters, not sentinels — UILabel/UITextView render an
            // embedded newline as an actual line break natively, and copy/paste,
            // re-parsing, and selection all see exactly this character, nothing
            // hidden. This also lets emphasis (**bold** etc.) span across a line
            // break, since the whole paragraph is one string before the inline
            // scanner ever runs.
            let joined = rawLines.joined(separator: "\n")
            blocks.append(.paragraph(MarkdownInlineScanner.parse(joined, autolinkPlainURLs: autolinkPlainURLs)))
            i = j
        }
        return blocks
    }

    // MARK: - Classifiers

    private static func fenceMarker(_ trimmed: String) -> (marker: String, language: String?)? {
        for fence in ["```", "~~~"] where trimmed.hasPrefix(fence) {
            let lang = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
            return (fence, lang.isEmpty ? nil : lang)
        }
        return nil
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.count >= 3 && stripped.allSatisfy { $0 == first }
    }

    private static func atxHeading(_ trimmed: String) -> (Int, String)? {
        var level = 0
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx] == "#", level < 6 { level += 1; idx = trimmed.index(after: idx) }
        guard level > 0, idx < trimmed.endIndex, trimmed[idx] == " " else { return nil }
        return (level, trimmed[trimmed.index(after: idx)...].trimmingCharacters(in: .whitespaces))
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func tableDelimiter(_ line: String) -> [MarkdownTableAlignment]? {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard c.allSatisfy({ $0 == "-" || $0 == ":" }), c.contains("-") else { return nil }
            switch (c.hasPrefix(":"), c.hasSuffix(":")) {
            case (true, true): alignments.append(.center)
            case (true, false): alignments.append(.left)
            case (false, true): alignments.append(.right)
            default: alignments.append(.none)
            }
        }
        return alignments
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        var cells: [String] = []
        var current = ""
        let chars = Array(t)
        var k = 0
        while k < chars.count {
            if chars[k] == "\\", k + 1 < chars.count, chars[k + 1] == "|" { current.append("|"); k += 2; continue }
            if chars[k] == "|" { cells.append(current.trimmingCharacters(in: .whitespaces)); current = ""; k += 1; continue }
            current.append(chars[k]); k += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func standaloneImage(_ trimmed: String) -> (String, String)? {
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")") else { return nil }
        let nodes = MarkdownInlineScanner.parse(trimmed, autolinkPlainURLs: false)
        if nodes.count == 1, case let .image(alt, url) = nodes[0] { return (alt, url) }
        return nil
    }

    private enum ListMarkerKind {
        case bullet
        case ordered(Int)
        /// A bullet item that starts with `[ ]` or `[x]`/`[X]` — a GFM task
        /// list item. Kept as a variant of bullet (not a separate marker
        /// family) so a list can freely mix plain bullets and checkboxes,
        /// exactly like real Markdown does.
        case task(checked: Bool)
    }

    private static func listMarker(_ line: String) -> (indent: Int, kind: ListMarkerKind, content: String)? {
        let chars = Array(line)
        var i = 0, indent = 0
        while i < chars.count, chars[i] == " " { indent += 1; i += 1 }
        guard i < chars.count else { return nil }
        if chars[i] == "-" || chars[i] == "*" || chars[i] == "+" {
            guard i + 1 < chars.count, chars[i + 1] == " " else { return nil }
            let rest = String(chars[(i + 2)...])
            if let (checked, content) = taskCheckbox(in: rest) {
                return (indent, .task(checked: checked), content)
            }
            return (indent, .bullet, rest)
        }
        var numStr = ""
        var j = i
        while j < chars.count, chars[j].isNumber { numStr.append(chars[j]); j += 1 }
        guard !numStr.isEmpty, j < chars.count, (chars[j] == "." || chars[j] == ")"),
              j + 1 < chars.count, chars[j + 1] == " ", let num = Int(numStr) else { return nil }
        return (indent, .ordered(num), String(chars[(j + 2)...]))
    }

    /// Matches GFM's task-list checkbox: exactly `[ ]` or `[x]`/`[X]`
    /// followed by a space, right at the start of a bullet item's content.
    /// Deliberately narrow — `- [note] text` (anything other than a blank
    /// or x/X between the brackets) is left as a plain bullet whose text
    /// happens to start with "[note]", not misread as a checkbox.
    private static func taskCheckbox(in text: String) -> (checked: Bool, content: String)? {
        let chars = Array(text)
        guard chars.count > 3, chars[0] == "[", chars[2] == "]", chars[3] == " " else { return nil }
        switch chars[1] {
        case " ": return (false, String(chars[4...]))
        case "x", "X": return (true, String(chars[4...]))
        default: return nil
        }
    }

    private static func collectList(_ lines: [String], from start: Int,
                                     markerKind: (indent: Int, kind: ListMarkerKind, content: String)) -> (items: [[String]], checked: [Bool?], ordered: Bool, start: Int, consumed: Int) {
        let baseIndent = markerKind.indent
        let ordered: Bool, startNumber: Int
        switch markerKind.kind {
        case .bullet, .task: ordered = false; startNumber = 1
        case .ordered(let n): ordered = true; startNumber = n
        }

        func checkedValue(for kind: ListMarkerKind) -> Bool? {
            if case .task(let checked) = kind { return checked }
            return nil
        }

        var items: [[String]] = []
        var checkedStates: [Bool?] = [checkedValue(for: markerKind.kind)]
        var current: [String] = [markerKind.content]
        var i = start + 1

        func isSameLevelMarker(_ line: String) -> Bool {
            guard let m = listMarker(line), m.indent == baseIndent else { return false }
            switch (m.kind, markerKind.kind) {
            case (.ordered, .ordered): return true
            case (.ordered, _), (_, .ordered): return false
            default: return true // bullet and task share one list family
            }
        }

        while i < lines.count {
            let line = lines[i]
            if isSameLevelMarker(line) {
                items.append(current)
                let m = listMarker(line)!
                current = [m.content]
                checkedStates.append(checkedValue(for: m.kind))
                i += 1; continue
            }
            let indentCount = line.prefix { $0 == " " }.count
            let isEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isEmpty {
                let nextIsNested = i + 1 < lines.count && (listMarker(lines[i + 1])?.indent ?? -1) > baseIndent
                if nextIsNested { current.append(""); i += 1; continue } else { break }
            }
            if indentCount > baseIndent {
                let dedent = min(indentCount, baseIndent + 2)
                current.append(String(line.dropFirst(dedent)))
                i += 1; continue
            }
            break
        }
        items.append(current)
        return (items, checkedStates, ordered, startNumber, i - start)
    }
}
