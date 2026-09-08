//
//  BiDiMarkdownView.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import SwiftUI

/// A SwiftUI view that renders a Markdown string with correct bidirectional
/// (mixed Hebrew/Arabic and Latin-script) text layout.
///
/// Unlike general-purpose Markdown renderers, `BiDiMarkdownView` resolves
/// text direction independently for each block — heading, paragraph, list
/// item, table — using the Unicode first-strong-character rule, so a single
/// document can correctly mix English and Hebrew or Arabic content without
/// every block being forced to the same direction.
///
/// ```swift
/// BiDiMarkdownView(markdown: "# שלום, World\n\nMixed **content** works.")
/// ```
///
/// It wraps a native renderer (UIKit on iOS, AppKit on macOS) — there's no
/// `WKWebView`, no JavaScript, and no external Markdown engine involved.
/// Only this view, ``MarkdownTextDirection``, and ``MarkdownStyle`` are
/// public; everything else (the parser, the AST, the platform-specific view
/// internals) is free to change without breaking code that depends on this
/// package.
///
/// ## Topics
/// ### Creating a view
/// - ``init(markdown:direction:style:autolinkPlainURLs:onLinkTap:)``
/// ### Controlling direction and appearance
/// - ``MarkdownTextDirection``
/// - ``MarkdownStyle``
public struct BiDiMarkdownView: View {
    private let markdown: String
    private let direction: MarkdownTextDirection
    private let style: MarkdownStyle
    private let autolinkPlainURLs: Bool
    private let onLinkTap: ((URL) -> Void)?

    /// Creates a Markdown view.
    ///
    /// - Parameters:
    ///   - markdown: The Markdown source to render.
    ///   - direction: How to resolve each block's text direction. Defaults
    ///     to ``MarkdownTextDirection/auto``, which inspects each block's own
    ///     content rather than applying one direction to the whole document.
    ///   - style: Colors and font sizes to use. Defaults to
    ///     ``MarkdownStyle/init(textColor:linkColor:codeTextColor:codeBackgroundColor:inlineCodeBackgroundColor:quoteBarColor:bodyFontSize:codeFontSize:)``'s
    ///     system-adaptive defaults.
    ///   - autolinkPlainURLs: When `true` (the default), a bare URL in the
    ///     text — `https://example.com` or `www.example.com`, not wrapped in
    ///     `[text](url)` syntax — becomes a tappable link on its own. Set to
    ///     `false` if you'd rather only explicit `[text](url)` links be
    ///     tappable.
    ///   - onLinkTap: Called when the person taps or clicks a link — an
    ///     inline `[text](url)` link, an autolinked bare URL, or an image.
    ///     If you don't supply this, links are inert (no default "open in
    ///     browser" behavior).
    public init(
        markdown: String,
        direction: MarkdownTextDirection = .auto,
        style: MarkdownStyle = MarkdownStyle(),
        autolinkPlainURLs: Bool = true,
        onLinkTap: ((URL) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.direction = direction
        self.style = style
        self.autolinkPlainURLs = autolinkPlainURLs
        self.onLinkTap = onLinkTap
    }

    public var body: some View {
        MarkdownTextView(markdown: markdown, direction: direction, style: style, autolinkPlainURLs: autolinkPlainURLs, onLinkTap: onLinkTap)
    }
}
