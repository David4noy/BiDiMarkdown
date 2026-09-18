//
//  MarkdownView.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

protocol MarkdownViewDelegate: AnyObject {
    func markdownView(_ view: MarkdownView, didTapLink url: URL)
    func markdownView(_ view: MarkdownView, didTapImage url: URL)
    func markdownView(_ view: MarkdownView, didCopyCode code: String)
}

final class MarkdownView: PlatformViewBase, PlatformTextViewDelegate {
    weak var delegate: MarkdownViewDelegate?

    private(set) var direction: MarkdownTextDirection = .auto
    private(set) var style = MarkdownStyle()
    var tableMaxHeight: CGFloat?
    private(set) var autolinkPlainURLs = true

    /// Bumped only when the arranged-subview tree is actually torn down and
    /// rebuilt (see `render` below) — lets external code tell a genuine
    /// content change apart from a no-op `render` call.
    private(set) var contentVersion = 0

    private var lastRenderedMarkdown: String?
    private let stack = PlatformStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Single entry point for (re)rendering. SwiftUI calls this on every
    /// `updateUIView`/`updateNSView`, which happens far more often than the
    /// markdown actually changes (e.g. on any relayout elsewhere in the
    /// hierarchy, including tab switches, or after an async image load
    /// resizes a subview). Rebuilding unconditionally used to tear down
    /// every subview and recreate every `MarkdownImageView` from scratch on
    /// every call, which restarted a network fetch for every image every
    /// time — and each image finishing its (new) load resizes a height
    /// constraint, which is exactly the kind of layout change that makes
    /// SwiftUI re-invoke the update method. That closed a self-feeding loop
    /// that never settled (the "freezes and doesn't release" symptom).
    /// Skipping the rebuild when nothing actually changed breaks that loop
    /// at the source.
    func render(markdown: String, direction: MarkdownTextDirection, style: MarkdownStyle? = nil, tableMaxHeight: CGFloat? = nil, autolinkPlainURLs: Bool = true) {
        let resolvedStyle = style ?? self.style
        let resolvedTableMaxHeight = tableMaxHeight ?? self.tableMaxHeight

        guard markdown != lastRenderedMarkdown
            || direction != self.direction
            || resolvedStyle != self.style
            || resolvedTableMaxHeight != self.tableMaxHeight
            || autolinkPlainURLs != self.autolinkPlainURLs
        else {
            return
        }

        self.direction = direction
        self.style = resolvedStyle
        self.tableMaxHeight = resolvedTableMaxHeight
        self.autolinkPlainURLs = autolinkPlainURLs
        lastRenderedMarkdown = markdown

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for block in MarkdownParser.parse(markdown, autolinkPlainURLs: autolinkPlainURLs) {
            addFullWidthArrangedSubview(buildView(for: block), to: stack)
        }
        contentVersion += 1
    }

    /// The natural (unwrapped, but still respecting the content's own hard
    /// line breaks) width this content would need — or nil if the content
    /// isn't simple enough for that to be an unambiguous question. Only
    /// non-nil for exactly one paragraph or heading and nothing else; a
    /// list, table, quote, image, or code block all have their own width
    /// semantics that a single string measurement can't capture correctly,
    /// so those are left alone entirely (nil here means "just fill the
    /// proposed width," the original, always-safe behavior).
    ///
    /// Deliberately measured via `NSAttributedString.boundingRect` directly
    /// on the string — never by asking the wrapping UITextView/NSTextView
    /// itself to report a "compressed" size. A view that's allowed to wrap
    /// has no well-defined minimum width (it can always wrap narrower, down
    /// to its widest single word), so asking Auto Layout to compress it
    /// collapses to roughly that instead of anything useful — that's
    /// exactly what went wrong the first time this was attempted. Measuring
    /// the plain string directly, unconstrained, doesn't involve wrapping
    /// or Auto Layout at all, so that failure mode doesn't apply here.
    var singleBlockNaturalWidth: CGFloat? {
        guard stack.arrangedSubviews.count == 1,
              let textView = stack.arrangedSubviews.first as? MarkdownParagraphTextView,
              let text = textView.attributedText, text.length > 0
        else { return nil }

        let bounds = text.boundingRect(
            with: CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        // +1pt buffer: boundingRect's glyph-based measurement and TextKit's
        // actual line-fragment layout can differ by a hair; without this,
        // a width that's a fraction of a point too narrow could still
        // trigger an unwanted wrap right at the edge.
        return ceil(bounds.width) + 1
    }

    private func buildView(for block: MarkdownBlockNode) -> PlatformView {
        switch block {
        case .heading(let level, let inline):
            return textView(inline, font: MarkdownFonts.heading(level: level))
        case .paragraph(let inline):
            return textView(inline, font: MarkdownFonts.body(style.bodyFontSize))
        case .codeBlock(let language, let code):
            let v = MarkdownCodeBlockView(code: code, language: language, style: style)
            v.delegate = self
            return v
        case .blockQuote(let children):
            return MarkdownBlockquoteView(childViews: children.map { buildView(for: $0) }, direction: direction, style: style, sampleText: plainText(of: children))
        case .unorderedList(let items, let checked, _):
            return listStack(items: items, checked: checked, ordered: false, start: 1)
        case .orderedList(let start, let items, _):
            return listStack(items: items, checked: Array(repeating: nil, count: items.count), ordered: true, start: start)
        case .table(let alignments, let header, let rows):
            let v = MarkdownTableView(alignments: alignments, header: header, rows: rows, direction: direction, style: style, maxHeight: tableMaxHeight)
            v.delegate = self
            return v
        case .image(let alt, let url):
            let v = MarkdownImageView(alt: alt, urlString: url, style: style)
            v.delegate = self
            return v
        case .horizontalRule:
            return MarkdownHorizontalRuleView()
        }
    }

    private func textView(_ inline: [MarkdownInlineNode], font: PlatformFont) -> PlatformView {
        let v = MarkdownParagraphTextView()
        let plain = plainText(of: inline)
        let builder = MarkdownInlineAttributedStringBuilder(direction: direction, style: style)
        v.attributedText = builder.build(inline, font: font, plainText: plain)
        v.delegate = self
        return v
    }

    private func listStack(items: [[MarkdownBlockNode]], checked: [Bool?], ordered: Bool, start: Int) -> PlatformView {
        let container = PlatformStackView()
        container.axis = .vertical
        container.spacing = 6
        for (idx, itemBlocks) in items.enumerated() {
            let isChecked = idx < checked.count ? checked[idx] : nil
            let marker: String
            if let isChecked {
                marker = isChecked ? "☑" : "☐" // task-list item — nil means "not a task item"
            } else {
                marker = ordered ? "\(start + idx)." : "•"
            }
            let itemStack = PlatformStackView()
            itemStack.axis = .vertical
            itemStack.spacing = 6
            itemBlocks.forEach {
                let view = buildView(for: $0)
                if isChecked == true { applyCompletedTaskStrikethrough(to: view) }
                addFullWidthArrangedSubview(view, to: itemStack)
            }
            let row = MarkdownListItemRowView(markerText: marker, contentView: itemStack, direction: direction, style: style, sampleText: plainText(of: itemBlocks), taskChecked: isChecked)
            addFullWidthArrangedSubview(row, to: container)
        }
        return container
    }

    /// Strikes through a checked task item's own text (paragraph/heading
    /// content). Only affects the item's direct text — a nested list inside
    /// a checked item isn't itself a `MarkdownParagraphTextView`, so its
    /// sub-items are left alone, matching how most rendered task lists
    /// behave (only the completed item's own line is struck through).
    private func applyCompletedTaskStrikethrough(to view: PlatformView) {
        guard let textView = view as? MarkdownParagraphTextView, let text = textView.attributedText else { return }
        let mutable = NSMutableAttributedString(attributedString: text)
        mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: mutable.length))
        textView.attributedText = mutable
    }

    private func plainText(of blocks: [MarkdownBlockNode]) -> String {
        blocks.map { block -> String in
            switch block {
            case .heading(_, let i), .paragraph(let i): return plainText(of: i)
            case .codeBlock(_, let c): return c
            case .blockQuote(let b): return plainText(of: b)
            case .unorderedList(let items, _, _), .orderedList(_, let items, _):
                return items.map { plainText(of: $0) }.joined(separator: " ")
            case .table(_, let header, let rows):
                return (header + rows.flatMap { $0 }).map { plainText(of: $0) }.joined(separator: " ")
            case .image(let alt, _): return alt
            case .horizontalRule: return ""
            }
        }.joined(separator: " ")
    }

    private func plainText(of nodes: [MarkdownInlineNode]) -> String {
        nodes.map { node -> String in
            switch node {
            case .text(let s): return s
            case .bold(let c), .italic(let c), .boldItalic(let c), .strikethrough(let c): return plainText(of: c)
            case .code(let s): return s
            case .link(let t, _): return plainText(of: t)
            case .image(let alt, _): return alt
            }
        }.joined()
    }

    #if canImport(UIKit)
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        delegate?.markdownView(self, didTapLink: URL)
        return false
    }
    #elseif canImport(AppKit)
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            delegate?.markdownView(self, didTapLink: url)
        }
        return true
    }
    #endif
}

extension MarkdownView: MarkdownCodeBlockViewDelegate {
    func markdownCodeBlockView(_ view: MarkdownCodeBlockView, didTapCopy code: String) {
        delegate?.markdownView(self, didCopyCode: code)
    }
}
extension MarkdownView: MarkdownTableViewDelegate {
    func markdownTableView(_ view: MarkdownTableView, didTapLink url: URL) {
        delegate?.markdownView(self, didTapLink: url)
    }
}
extension MarkdownView: MarkdownImageViewDelegate {
    func markdownImageView(_ view: MarkdownImageView, didTap url: URL) {
        delegate?.markdownView(self, didTapImage: url)
    }
}
