//
//  MarkdownTableView.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

protocol MarkdownTableViewDelegate: AnyObject {
    func markdownTableView(_ view: MarkdownTableView, didTapLink url: URL)
}

final class MarkdownTableView: PlatformViewBase, PlatformTextViewDelegate {
    weak var delegate: MarkdownTableViewDelegate?

    init(alignments: [MarkdownTableAlignment], header: [[MarkdownInlineNode]], rows: [[[MarkdownInlineNode]]],
         direction: MarkdownTextDirection, style: MarkdownStyle, maxHeight: CGFloat?) {
        super.init(frame: .zero)
        setup(alignments: alignments, header: header, rows: rows, direction: direction, style: style, maxHeight: maxHeight)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup(alignments: [MarkdownTableAlignment], header: [[MarkdownInlineNode]], rows: [[[MarkdownInlineNode]]],
                        direction: MarkdownTextDirection, style: MarkdownStyle, maxHeight: CGFloat?) {
        let combinedText = (header + rows.flatMap { $0 }).map { plainText(of: $0) }.joined(separator: " ")
        let resolved = MarkdownDirectionResolver.resolvedDirection(for: direction, sampleText: combinedText)
        let isRTL = resolved == .rightToLeft

        // Column mirroring for RTL is done purely by reversing the arrays
        // before building rows, then laying cells out left-to-right as
        // normal — deliberately not via a per-view "force RTL" flag. UIKit
        // has one (`semanticContentAttribute`) but AppKit has no per-view
        // equivalent at all, so this had to work without it on either
        // platform anyway. Reversed array + plain left-to-right stacking is
        // self-evidently correct: index 0 (now the last logical column)
        // lands physically leftmost, the first logical column lands
        // physically rightmost — which is exactly what an RTL table needs.
        var displayHeader = header
        var displayRows = rows
        var displayAlignments = alignments
        if isRTL {
            displayHeader.reverse()
            displayRows = displayRows.map { $0.reversed() }
            displayAlignments.reverse()
        }

        let grid = PlatformStackView()
        grid.axis = .vertical
        grid.spacing = 0

        // Deliberately plain `addArrangedSubview`, not the full-width helper
        // used elsewhere in this module: grid's width should be DERIVED from
        // its rows' content (so the table can size to fit, or scroll if it's
        // wider than the container), not forced onto them. Forcing every row
        // to match grid's width while also expecting grid's width to come
        // from its rows is circular, and is very likely why this table
        // rendered at some fixed/wrong size instead of sizing to content.
        grid.addArrangedSubview(
            buildRow(cells: displayHeader, alignments: displayAlignments, direction: direction, style: style, isHeader: true)
        )
        for row in displayRows {
            grid.addArrangedSubview(
                buildRow(cells: row, alignments: displayAlignments, direction: direction, style: style, isHeader: false)
            )
        }

        if let firstRow = grid.arrangedSubviews.first as? PlatformStackView {
            for (colIndex, referenceCell) in firstRow.arrangedSubviews.enumerated() {
                for rowView in grid.arrangedSubviews.dropFirst() {
                    guard let row = rowView as? PlatformStackView, colIndex < row.arrangedSubviews.count else { continue }
                    row.arrangedSubviews[colIndex].widthAnchor.constraint(equalTo: referenceCell.widthAnchor).isActive = true
                }
            }
        }

        let scrollView = MarkdownTableScrollView()
        scrollView.isRTL = isRTL
        grid.translatesAutoresizingMaskIntoConstraints = false
        #if canImport(UIKit)
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor)
        ])
        #elseif canImport(AppKit)
        // NSScrollView needs an explicit `documentView`; UIScrollView has no
        // equivalent concept. Only the origin corner (top+leading) is
        // pinned — no width or bottom constraint — so grid's size comes
        // purely from its own content (rows sized from their cells' real
        // intrinsic widths, see MarkdownParagraphTextView.SizingMode) in
        // both dimensions, and either axis scrolls independently once
        // content exceeds the viewport. This mirrors how
        // MarkdownCodeBlockView's scroll view is set up.
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = grid
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            grid.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor)
        ])
        #endif

        let naturalHeight = scrollView.heightAnchor.constraint(equalTo: grid.heightAnchor)
        naturalHeight.priority = PlatformLayoutPriority(999)
        naturalHeight.isActive = true
        if let maxHeight {
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight).isActive = true
        }

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        applyCardAppearance(cornerRadius: 6, borderColor: .separator, borderWidth: 1)
    }

    private func buildRow(cells: [[MarkdownInlineNode]], alignments: [MarkdownTableAlignment], direction: MarkdownTextDirection,
                           style: MarkdownStyle, isHeader: Bool) -> PlatformStackView {
        let row = PlatformStackView()
        row.axis = .horizontal
        row.distribution = .fill

        for (idx, cellNodes) in cells.enumerated() {
            let align = idx < alignments.count ? alignments[idx] : .none
            let cellView = MarkdownParagraphTextView()
            cellView.delegate = self
            let builder = MarkdownInlineAttributedStringBuilder(direction: direction, style: style)
            let font = isHeader ? MarkdownFonts.heading(level: 6) : MarkdownFonts.body(style.bodyFontSize)
            let text = plainText(of: cellNodes)
            cellView.attributedText = builder.build(cellNodes, font: font, plainText: text)
            cellView.textAlignment = tableCellAlignment(align, direction: direction, cellText: text)
            #if canImport(AppKit)
            cellView.sizingMode = .intrinsicSize
            #endif
            cellView.applyBackgroundColor(isHeader ? .secondarySystemBackground : .clear)
            #if canImport(UIKit)
            cellView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            #elseif canImport(AppKit)
            cellView.textContainerInset = NSSize(width: 10, height: 8)
            #endif
            cellView.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

            let wrapper = PlatformView()
            wrapper.applyCardAppearance(cornerRadius: 0, borderColor: .separator, borderWidth: 0.5)
            wrapper.addSubview(cellView)
            cellView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                cellView.topAnchor.constraint(equalTo: wrapper.topAnchor),
                cellView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                cellView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                cellView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor)
            ])
            addFullHeightArrangedSubview(wrapper, to: row)
        }
        return row
    }

    private func tableCellAlignment(_ align: MarkdownTableAlignment, direction: MarkdownTextDirection, cellText: String) -> NSTextAlignment {
        switch align {
        case .left: return .left
        case .right: return .right
        case .center: return .center
        case .none:
            let resolved = MarkdownDirectionResolver.resolvedDirection(for: direction, sampleText: cellText)
            return direction == .auto ? .natural : resolved.textAlignment
        }
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
        delegate?.markdownTableView(self, didTapLink: URL)
        return false
    }
    #elseif canImport(AppKit)
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            delegate?.markdownTableView(self, didTapLink: url)
        }
        return true // suppress NSTextView's own NSWorkspace.open — we report it via delegate instead, same as the UIKit side
    }
    #endif
}

/// A scroll view that, for RTL tables, starts scrolled to its trailing
/// (visually right) edge instead of the default leading/left edge.
///
/// Column order is already mirrored for RTL (see the comment in `setup`
/// above) — the first logical column ends up physically rightmost. But a
/// plain scroll view always starts scrolled to (0, 0), the physical LEFT
/// edge, regardless of that mirroring. For a table wider than its
/// container, that meant an RTL table opened showing its *last* logical
/// columns first — backwards for RTL reading. This performs the
/// corresponding one-time adjustment once the content size is known,
/// without fighting the person's own subsequent scrolling.
final class MarkdownTableScrollView: PlatformScrollView {
    var isRTL = false
    private var didPerformInitialScroll = false

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        guard isRTL, !didPerformInitialScroll, contentSize.width > bounds.width else { return }
        didPerformInitialScroll = true
        contentOffset = CGPoint(x: contentSize.width - bounds.width, y: contentOffset.y)
    }
    #elseif canImport(AppKit)
    override func layout() {
        super.layout()
        guard isRTL, !didPerformInitialScroll,
              let documentView, documentView.frame.width > contentView.bounds.width else { return }
        didPerformInitialScroll = true
        let targetX = documentView.frame.width - contentView.bounds.width
        contentView.scroll(to: NSPoint(x: targetX, y: 0))
        reflectScrolledClipView(contentView)
    }
    #endif
}
