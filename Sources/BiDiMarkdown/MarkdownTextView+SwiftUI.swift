//
//  MarkdownTextView+SwiftUI.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import SwiftUI

#if canImport(UIKit)

struct MarkdownTextView: UIViewRepresentable {
    let markdown: String
    let direction: MarkdownTextDirection
    var style: MarkdownStyle = MarkdownStyle()
    var autolinkPlainURLs: Bool = true
    var onLinkTap: ((URL) -> Void)? = nil

    func makeUIView(context: Context) -> MarkdownView {
        let v = MarkdownView()
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ uiView: MarkdownView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        uiView.render(markdown: markdown, direction: direction, style: style, autolinkPlainURLs: autolinkPlainURLs)
    }

    /// SwiftUI proposes a width (from the enclosing layout); we lay the
    /// UIKit side out at that width via Auto Layout and measure the
    /// resulting height. Called independently of `updateUIView` — `render`
    /// above is a no-op when nothing changed, but this can still legitimately
    /// re-run afterwards (e.g. once an async image load resizes a subview).
    ///
    /// The width used is the proposed width, UNLESS this content is simple
    /// enough (see `singleBlockNaturalWidth`) to have an unambiguous smaller
    /// natural width — a short single-line message inside `.frame(maxWidth:)`
    /// hugs its own width instead of stretching to fill it. Either way, the
    /// width is fully decided BEFORE Auto Layout ever measures anything —
    /// this never asks Auto Layout itself to find a "compressed" size for
    /// wrapping content, which has no well-defined answer and collapses
    /// badly (see `singleBlockNaturalWidth`'s doc comment).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownView, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth > 0, proposedWidth.isFinite else { return nil }
        let width = uiView.singleBlockNaturalWidth.map { min($0, proposedWidth) } ?? proposedWidth
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let fitting = uiView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MarkdownViewDelegate {
        var onLinkTap: ((URL) -> Void)?
        func markdownView(_ view: MarkdownView, didTapLink url: URL) { onLinkTap?(url) }
        func markdownView(_ view: MarkdownView, didTapImage url: URL) { onLinkTap?(url) }
        func markdownView(_ view: MarkdownView, didCopyCode code: String) {}
    }
}

#elseif canImport(AppKit)

// UNVERIFIED ON A REAL BUILD. NSViewRepresentable mirrors
// UIViewRepresentable closely (same idea, `makeNSView`/`updateNSView`
// instead of `makeUIView`/`updateUIView`, `sizeThatFits(_:nsView:context:)`
// added in the same SwiftUI release as the UIKit one), but there's no
// shared protocol to conform to once — hence a second, separate conformance
// rather than one shared implementation.
struct MarkdownTextView: NSViewRepresentable {
    let markdown: String
    let direction: MarkdownTextDirection
    var style: MarkdownStyle = MarkdownStyle()
    var autolinkPlainURLs: Bool = true
    var onLinkTap: ((URL) -> Void)? = nil

    func makeNSView(context: Context) -> MarkdownView {
        let v = MarkdownView()
        v.delegate = context.coordinator
        return v
    }

    func updateNSView(_ nsView: MarkdownView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        nsView.render(markdown: markdown, direction: direction, style: style, autolinkPlainURLs: autolinkPlainURLs)
    }

    /// Same reasoning as the UIKit version's doc comment. `fittingSize(
    /// forConstrainedWidth:)` is only ever called with a width that's
    /// already fully decided (the proposal, or a smaller natural width for
    /// simple content) — never asked to find its own "compressed" size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownView, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width, proposedWidth > 0, proposedWidth.isFinite else { return nil }
        let width = nsView.singleBlockNaturalWidth.map { min($0, proposedWidth) } ?? proposedWidth
        return nsView.fittingSize(forConstrainedWidth: width)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MarkdownViewDelegate {
        var onLinkTap: ((URL) -> Void)?
        func markdownView(_ view: MarkdownView, didTapLink url: URL) { onLinkTap?(url) }
        func markdownView(_ view: MarkdownView, didTapImage url: URL) { onLinkTap?(url) }
        func markdownView(_ view: MarkdownView, didCopyCode code: String) {}
    }
}

private extension NSView {
    /// AppKit has no direct equivalent of `systemLayoutSizeFitting` for an
    /// arbitrary constrained width — this pins a temporary width constraint,
    /// asks Auto Layout to resolve it, reads the result, then removes it.
    /// UNVERIFIED: works in principle (Auto Layout doesn't care whether the
    /// view is on screen to resolve constraints), but the temporary-
    /// constraint dance is the kind of thing that's easy to get subtly
    /// wrong without seeing it actually run.
    func fittingSize(forConstrainedWidth width: CGFloat) -> NSSize {
        let widthConstraint = widthAnchor.constraint(equalToConstant: width)
        widthConstraint.isActive = true
        layoutSubtreeIfNeeded()
        let size = fittingSize
        widthConstraint.isActive = false
        return size
    }
}

#endif
