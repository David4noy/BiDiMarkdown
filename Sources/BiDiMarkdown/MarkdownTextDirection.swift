//
//  MarkdownTextDirection.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// How ``BiDiMarkdownView`` decides the reading direction of each block —
/// heading, paragraph, list item, table.
public enum MarkdownTextDirection: String, CaseIterable {
    /// Resolve each block's direction independently from its own content,
    /// using the Unicode first-strong-character rule (the same heuristic
    /// the Unicode Bidirectional Algorithm uses to pick a paragraph's base
    /// direction). This is what makes a single document work correctly when
    /// it mixes English paragraphs with Hebrew or Arabic ones. The default.
    case auto
    /// Force every block to right-to-left, regardless of its content.
    /// Useful when you already know the whole document is RTL and want to
    /// skip per-block detection (or override a false detection).
    case rtl
    /// Force every block to left-to-right, regardless of its content.
    case ltr
}

enum ResolvedDirection {
    case leftToRight
    case rightToLeft

    var textAlignment: NSTextAlignment {
        self == .leftToRight ? .left : .right
    }
}

enum MarkdownDirectionResolver {

    /// Glyph/run-level direction handed to NSParagraphStyle. For .auto this is
    /// `.natural` — the text engine applies the real Unicode Bidi Algorithm per
    /// paragraph (first-strong-character rule), which is what correctly
    /// interleaves Hebrew/English runs on the same line. We never hand-roll
    /// bidi reordering.
    static func baseWritingDirection(for mode: MarkdownTextDirection) -> NSWritingDirection {
        switch mode {
        case .auto: return .natural
        case .rtl: return .rightToLeft
        case .ltr: return .leftToRight
        }
    }

    /// Resolved direction for block-level layout decisions that
    /// NSParagraphStyle doesn't cover (list marker side, blockquote bar side,
    /// table column order). For .auto this applies the same first-strong rule
    /// UBA uses, restricted to Hebrew/Arabic as strong-RTL — dependency-free,
    /// no external Unicode tables needed. Callers turn this into concrete
    /// layout (which anchor to pin, which side of an array to reverse)
    /// themselves — there's no per-view "force this direction" API shared by
    /// both UIKit and AppKit, so that decision lives at each call site.
    static func resolvedDirection(for mode: MarkdownTextDirection, sampleText: String) -> ResolvedDirection {
        switch mode {
        case .rtl: return .rightToLeft
        case .ltr: return .leftToRight
        case .auto: return firstStrongDirection(in: sampleText)
        }
    }

    private static func firstStrongDirection(in text: String) -> ResolvedDirection {
        for scalar in text.unicodeScalars {
            if isStrongRTL(scalar) { return .rightToLeft }
            if isStrongLTR(scalar) { return .leftToRight }
        }
        return .leftToRight
    }

    private static func isStrongRTL(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if (0x0590...0x05FF).contains(v) || (0xFB1D...0xFB4F).contains(v) { return true } // Hebrew
        if (0x0600...0x06FF).contains(v) || (0x0750...0x077F).contains(v)
            || (0x08A0...0x08FF).contains(v) || (0xFB50...0xFDFF).contains(v)
            || (0xFE70...0xFEFF).contains(v) { return true } // Arabic
        return false
    }

    private static func isStrongLTR(_ scalar: Unicode.Scalar) -> Bool {
        guard !isStrongRTL(scalar) else { return false }
        return CharacterSet.letters.contains(scalar)
    }
}
