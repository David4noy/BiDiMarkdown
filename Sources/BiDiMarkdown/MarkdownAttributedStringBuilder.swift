//
//  MarkdownAttributedStringBuilder.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum MarkdownFonts {
    static func body(_ size: CGFloat) -> PlatformFont { .systemFont(ofSize: size) }
    static func heading(level: Int) -> PlatformFont {
        let sizes: [Int: CGFloat] = [1: 26, 2: 23, 3: 20, 4: 18, 5: 17, 6: 16]
        return .systemFont(ofSize: sizes[level] ?? 16, weight: .bold)
    }
    static func code(_ size: CGFloat) -> PlatformFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
}

/// Colors and font sizes used by ``BiDiMarkdownView``.
///
/// Every default is a system-adaptive semantic color (`.label`,
/// `.secondarySystemBackground`, and so on), so a default-initialized
/// `MarkdownStyle` already respects light/dark mode and platform
/// conventions. Override only what you need:
///
/// ```swift
/// BiDiMarkdownView(markdown: text, style: MarkdownStyle(linkColor: .systemPurple))
/// ```
public struct MarkdownStyle: Equatable {
    /// Color for plain body and heading text. Default: `.label`.
    public var textColor: PlatformColor
    /// Color for link text (both `[text](url)` links and images). Default: `.systemBlue`.
    public var linkColor: PlatformColor
    /// Text color inside fenced code blocks. Default: `.label`.
    public var codeTextColor: PlatformColor
    /// Background color of fenced code blocks. Default: `.secondarySystemBackground`.
    public var codeBackgroundColor: PlatformColor
    /// Background color of inline `` `code` `` spans. Default: `.secondarySystemBackground`.
    public var inlineCodeBackgroundColor: PlatformColor
    /// Color of the vertical bar alongside blockquotes. Default: `.systemGray3`.
    public var quoteBarColor: PlatformColor
    /// Font size, in points, for body text and list/quote content. Default: `16`.
    public var bodyFontSize: CGFloat
    /// Font size, in points, for fenced and inline code. Default: `14`.
    public var codeFontSize: CGFloat

    public init(
        textColor: PlatformColor = .label,
        linkColor: PlatformColor = .systemBlue,
        codeTextColor: PlatformColor = .label,
        codeBackgroundColor: PlatformColor = .secondarySystemBackground,
        inlineCodeBackgroundColor: PlatformColor = .secondarySystemBackground,
        quoteBarColor: PlatformColor = .systemGray3,
        bodyFontSize: CGFloat = 16,
        codeFontSize: CGFloat = 14
    ) {
        self.textColor = textColor
        self.linkColor = linkColor
        self.codeTextColor = codeTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.inlineCodeBackgroundColor = inlineCodeBackgroundColor
        self.quoteBarColor = quoteBarColor
        self.bodyFontSize = bodyFontSize
        self.codeFontSize = codeFontSize
    }
}

final class MarkdownInlineAttributedStringBuilder {
    let direction: MarkdownTextDirection
    let style: MarkdownStyle

    init(direction: MarkdownTextDirection, style: MarkdownStyle) {
        self.direction = direction
        self.style = style
    }

    func build(_ nodes: [MarkdownInlineNode], font: PlatformFont, plainText: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for node in nodes { result.append(render(node, font: font, bold: false, italic: false)) }

        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = MarkdownDirectionResolver.baseWritingDirection(for: direction)
        let resolved = MarkdownDirectionResolver.resolvedDirection(for: direction, sampleText: plainText)
        paragraph.alignment = direction == .auto ? .natural : resolved.textAlignment
        paragraph.lineSpacing = 2
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    private func render(_ node: MarkdownInlineNode, font: PlatformFont, bold: Bool, italic: Bool) -> NSAttributedString {
        switch node {
        case .text(let s):
            return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: style.textColor])
        case .bold(let c):
            return joined(c, font: styledFont(font, bold: true, italic: italic), bold: true, italic: italic)
        case .italic(let c):
            return joined(c, font: styledFont(font, bold: bold, italic: true), bold: bold, italic: true)
        case .boldItalic(let c):
            return joined(c, font: styledFont(font, bold: true, italic: true), bold: true, italic: true)
        case .strikethrough(let c):
            let attr = NSMutableAttributedString(attributedString: joined(c, font: font, bold: bold, italic: italic))
            attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attr.length))
            return attr
        case .code(let text):
            // .embedding (not .override) — sets the base direction to LTR for
            // neutral/ASCII code content without forcing character order. Hebrew
            // or other RTL characters that happen to appear inside a code span
            // still resolve correctly via the normal bidi algorithm; only the
            // run's default anchor is LTR, so it won't inherit the surrounding
            // RTL paragraph's alignment.
            let embedLTR = NSNumber(value: NSWritingDirection.leftToRight.rawValue | NSWritingDirectionFormatType.embedding.rawValue)
            return NSAttributedString(string: text, attributes: [
                .font: MarkdownFonts.code(style.codeFontSize),
                .foregroundColor: style.codeTextColor,
                .backgroundColor: style.inlineCodeBackgroundColor,
                .writingDirection: [embedLTR]
            ])
        case .link(let children, let urlString):
            let attr = NSMutableAttributedString(attributedString: joined(children, font: font, bold: bold, italic: italic))
            let range = NSRange(location: 0, length: attr.length)
            if let url = URL(string: urlString) { attr.addAttribute(.link, value: url, range: range) }
            attr.addAttribute(.foregroundColor, value: style.linkColor, range: range)
            return attr
        case .image(let alt, let url):
            return NSAttributedString(string: alt.isEmpty ? "[image]" : "[\(alt)]", attributes: [
                .font: font, .foregroundColor: style.linkColor, .link: URL(string: url) as Any
            ])
        }
    }

    /// UIFontDescriptor and NSFontDescriptor differ in more than name here:
    /// trait case names (`.traitBold`/`.traitItalic` vs `.bold`/`.italic`),
    /// `withSymbolicTraits` returning Optional on UIKit but not on AppKit,
    /// and `UIFont(descriptor:size:)` vs the failable `NSFont(descriptor:size:)`.
    /// Small enough surface that branching the whole function reads clearer
    /// than threading a shim through three separate differences.
    private func styledFont(_ font: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
        #if canImport(UIKit)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
        return UIFont(descriptor: descriptor, size: font.pointSize)
        #elseif canImport(AppKit)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }

    private func joined(_ nodes: [MarkdownInlineNode], font: PlatformFont, bold: Bool, italic: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for n in nodes { result.append(render(n, font: font, bold: bold, italic: italic)) }
        return result
    }
}
