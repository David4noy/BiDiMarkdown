//
//  MarkdownInlineScanner.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import Foundation

final class MarkdownInlineScanner {
    private let scalars: [Character]
    private var pos: Int = 0
    private let autolinkPlainURLs: Bool

    private init(_ text: String, autolinkPlainURLs: Bool) {
        self.scalars = Array(text)
        self.autolinkPlainURLs = autolinkPlainURLs
    }

    static func parse(_ text: String, autolinkPlainURLs: Bool = true) -> [MarkdownInlineNode] {
        MarkdownInlineScanner(text, autolinkPlainURLs: autolinkPlainURLs).scan()
    }

    private func scan() -> [MarkdownInlineNode] {
        var nodes: [MarkdownInlineNode] = []
        var buffer = ""

        func flush() {
            if !buffer.isEmpty { nodes.append(.text(buffer)); buffer = "" }
        }

        while pos < scalars.count {
            let c = scalars[pos]

            if c == "\\", pos + 1 < scalars.count {
                flush(); buffer.append(scalars[pos + 1]); pos += 2; continue
            }
            if c == "`", let (content, newPos) = scanCodeSpan(from: pos) {
                flush(); nodes.append(.code(content)); pos = newPos; continue
            }
            if c == "!", pos + 1 < scalars.count, scalars[pos + 1] == "[",
               let (alt, url, newPos) = scanLinkOrImageSyntax(from: pos + 1) {
                flush(); nodes.append(.image(alt: alt, url: url)); pos = newPos; continue
            }
            if c == "[", let (text, url, newPos) = scanLinkOrImageSyntax(from: pos) {
                flush(); nodes.append(.link(text: MarkdownInlineScanner.parse(text, autolinkPlainURLs: autolinkPlainURLs), url: url)); pos = newPos; continue
            }
            if (c == "*" || c == "_"), let (marker, content, newPos) = scanEmphasis(from: pos) {
                flush()
                let sub = MarkdownInlineScanner.parse(content, autolinkPlainURLs: autolinkPlainURLs)
                switch marker {
                case 3: nodes.append(.boldItalic(sub))
                case 2: nodes.append(.bold(sub))
                default: nodes.append(.italic(sub))
                }
                pos = newPos; continue
            }
            if c == "~", pos + 1 < scalars.count, scalars[pos + 1] == "~",
               let (content, newPos) = scanStrikethrough(from: pos) {
                flush(); nodes.append(.strikethrough(MarkdownInlineScanner.parse(content, autolinkPlainURLs: autolinkPlainURLs))); pos = newPos; continue
            }
            // A bare URL not wrapped in `[text](url)` or `<url>` syntax —
            // e.g. someone pasting "check https://example.com/x" straight
            // into a chat message. Doesn't run inside code spans (handled
            // above, before this point ever sees that content) or inside an
            // already-explicit link's URL portion (that's consumed directly
            // by scanLinkOrImageSyntax, never routed back through this loop).
            if autolinkPlainURLs, (c == "h" || c == "w"), let match = scanAutolink(from: pos) {
                flush(); nodes.append(.link(text: [.text(match.displayText)], url: match.url)); pos = match.newPos; continue
            }
            if c == "&", let (decoded, newPos) = scanEntity(from: pos) {
                buffer.append(decoded); pos = newPos; continue
            }

            buffer.append(c); pos += 1
        }
        flush()
        return nodes
    }

    private func scanCodeSpan(from start: Int) -> (String, Int)? {
        var fenceLen = 0
        var i = start
        while i < scalars.count, scalars[i] == "`" { fenceLen += 1; i += 1 }
        var j = i
        while j < scalars.count {
            if scalars[j] == "`" {
                var runLen = 0
                var k = j
                while k < scalars.count, scalars[k] == "`" { runLen += 1; k += 1 }
                if runLen == fenceLen {
                    return (String(scalars[i..<j]).trimmingCharacters(in: .whitespaces), k)
                }
                j = k
            } else { j += 1 }
        }
        return nil
    }

    private func scanLinkOrImageSyntax(from bracketStart: Int) -> (String, String, Int)? {
        guard scalars[bracketStart] == "[" else { return nil }
        var i = bracketStart + 1
        var depth = 1
        var textEnd = -1
        while i < scalars.count {
            if scalars[i] == "[" { depth += 1 }
            if scalars[i] == "]" { depth -= 1; if depth == 0 { textEnd = i; break } }
            i += 1
        }
        guard textEnd > 0, textEnd + 1 < scalars.count, scalars[textEnd + 1] == "(" else { return nil }
        let text = String(scalars[(bracketStart + 1)..<textEnd])
        var j = textEnd + 2
        var urlChars = ""
        var parenDepth = 1
        while j < scalars.count {
            if scalars[j] == "(" { parenDepth += 1 }
            if scalars[j] == ")" { parenDepth -= 1; if parenDepth == 0 { break } }
            urlChars.append(scalars[j]); j += 1
        }
        guard j < scalars.count, scalars[j] == ")" else { return nil }
        return (text, Self.stripTitle(from: urlChars.trimmingCharacters(in: .whitespaces)), j + 1)
    }

    /// CommonMark allows an optional title after the URL, e.g.
    /// `[text](https://example.com "My title")` — a space, then a
    /// double- or single-quoted title, as the last thing before the
    /// closing paren. Without this, the title text got concatenated
    /// straight into the URL string, and `URL(string:)` silently fails on
    /// a string containing a literal space and quotes — the link just
    /// went inert with no visible error. Titles themselves aren't rendered
    /// (no tooltip concept in this renderer); this only makes sure they
    /// don't corrupt the URL.
    private static func stripTitle(from raw: String) -> String {
        guard let spaceIndex = raw.firstIndex(of: " ") else { return raw }
        let urlPart = String(raw[raw.startIndex..<spaceIndex])
        let rest = raw[raw.index(after: spaceIndex)...].trimmingCharacters(in: .whitespaces)
        let looksLikeTitle = (rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2)
            || (rest.hasPrefix("'") && rest.hasSuffix("'") && rest.count >= 2)
        return looksLikeTitle ? urlPart : raw
    }

    /// Finds the matching CLOSE for an OPEN run of `*`/`_` of the same
    /// length, and treats everything between as the emphasis content.
    ///
    /// This is deliberately simpler than CommonMark's actual algorithm,
    /// which tracks a stack of "delimiter runs" and classifies each one as
    /// left-/right-flanking based on the whitespace and punctuation
    /// immediately around it (that's what lets CommonMark correctly decide,
    /// for instance, that `*` can open emphasis mid-word but `_` normally
    /// can't — `un*frigging*believable` is emphasis, `un_frigging_believable`
    /// isn't). None of that flanking analysis happens here; this just finds
    /// the next same-length run of the same character and treats it as the
    /// close, however it's surrounded. Every ordinary case (bold/italic
    /// wrapping a word or phrase, even nested) matches CommonMark's result
    /// — it's adversarial or ambiguous input (unmatched delimiters, mixed
    /// intraword `_` usage relying on flanking rules) where the two can
    /// diverge. Implementing the full delimiter-stack algorithm is a much
    /// bigger, separate undertaking — worth doing if a specific real input
    /// actually renders wrong, rather than speculatively.
    private func scanEmphasis(from start: Int) -> (Int, String, Int)? {
        let marker = scalars[start]
        var runLen = 0
        var i = start
        while i < scalars.count, scalars[i] == marker { runLen += 1; i += 1 }
        let openLen = min(runLen, 3)
        var j = i
        while j < scalars.count {
            if scalars[j] == marker {
                var closeLen = 0
                var k = j
                while k < scalars.count, scalars[k] == marker { closeLen += 1; k += 1 }
                if closeLen >= openLen {
                    let content = String(scalars[i..<j])
                    if content.isEmpty { return nil }
                    return (openLen, content, j + openLen)
                }
                j = k
            } else { j += 1 }
        }
        return nil
    }

    private func scanStrikethrough(from start: Int) -> (String, Int)? {
        guard start + 1 < scalars.count, scalars[start] == "~", scalars[start + 1] == "~" else { return nil }
        var j = start + 2
        while j < scalars.count - 1 {
            if scalars[j] == "~" && scalars[j + 1] == "~" {
                return (String(scalars[(start + 2)..<j]), j + 2)
            }
            j += 1
        }
        return nil
    }

    // MARK: - Autolinks (bare URLs, not wrapped in [text](url) or <url>)

    private func matchesLiteral(_ literal: String, at index: Int) -> Bool {
        let chars = Array(literal)
        guard index + chars.count <= scalars.count else { return false }
        for k in 0..<chars.count where scalars[index + k] != chars[k] { return false }
        return true
    }

    private func isAutolinkURLCharacter(_ c: Character) -> Bool {
        if c.isLetter || c.isNumber { return true }
        return "-._~:/?#[]@!$&'()*+,;=%".contains(c)
    }

    /// A reasonable, not-spec-exhaustive approximation of GFM's "extended
    /// autolink" rule: recognizes `http://`, `https://`, and `www.`, then
    /// consumes URL-safe characters, then trims trailing punctuation that's
    /// almost certainly sentence punctuation rather than part of the URL
    /// (a period ending a sentence, an unmatched closing paren from
    /// "(see https://example.com)"). `www.`-only matches get `https://`
    /// prepended for the actual link destination (so it's an openable
    /// absolute URL) but keep the originally-typed text as what's displayed.
    private func scanAutolink(from start: Int) -> (displayText: String, url: String, newPos: Int)? {
        let prefix: String
        if matchesLiteral("https://", at: start) { prefix = "https://" }
        else if matchesLiteral("http://", at: start) { prefix = "http://" }
        else if matchesLiteral("www.", at: start) { prefix = "www." }
        else { return nil }

        var i = start + prefix.count
        var body = ""
        while i < scalars.count, isAutolinkURLCharacter(scalars[i]) {
            body.append(scalars[i]); i += 1
        }
        guard !body.isEmpty, body.contains(".") else { return nil } // require at least a "." — bare "http://" or "www." alone isn't a link

        while let last = body.last, ".,;:!?\"'".contains(last) {
            body.removeLast(); i -= 1
        }
        while body.last == ")", body.filter({ $0 == "(" }).count < body.filter({ $0 == ")" }).count {
            body.removeLast(); i -= 1
        }
        guard !body.isEmpty else { return nil }

        let displayText = prefix + body
        let url = prefix == "www." ? "https://" + displayText : displayText
        return (displayText, url, i)
    }

    // MARK: - HTML entities

    private static let namedEntities: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "mdash": "—", "ndash": "–", "hellip": "…",
        "laquo": "«", "raquo": "»", "euro": "€", "times": "×", "divide": "÷"
    ]

    /// Decodes `&amp;`-style named entities (a small table of the ones that
    /// actually show up in practice — copy-pasted-from-a-webpage content is
    /// the main real-world source, not hand-typed markdown) plus `&#NNN;`
    /// / `&#xHH;` numeric references, which cover any character. An
    /// unrecognized `&...;` sequence, or a bare `&` not part of a valid
    /// entity, is left completely alone as a literal character — this never
    /// throws away text it doesn't understand.
    private func scanEntity(from start: Int) -> (Character, Int)? {
        var i = start + 1
        guard i < scalars.count else { return nil }

        if scalars[i] == "#" {
            i += 1
            var isHex = false
            if i < scalars.count, scalars[i] == "x" || scalars[i] == "X" { isHex = true; i += 1 }
            var digits = ""
            while i < scalars.count, (isHex ? scalars[i].isHexDigit : scalars[i].isNumber) {
                digits.append(scalars[i]); i += 1
            }
            guard !digits.isEmpty, i < scalars.count, scalars[i] == ";",
                  let codepoint = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(codepoint) else { return nil }
            return (Character(scalar), i + 1)
        }

        var name = ""
        while i < scalars.count, scalars[i].isLetter, name.count <= 10 {
            name.append(scalars[i]); i += 1
        }
        guard i < scalars.count, scalars[i] == ";", let decoded = Self.namedEntities[name] else { return nil }
        return (decoded, i + 1)
    }
}
