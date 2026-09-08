//
//  PlatformTypes.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

#if canImport(UIKit)
import UIKit

public typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
typealias PlatformView = UIView
typealias PlatformStackView = UIStackView
typealias PlatformImage = UIImage
typealias PlatformImageView = UIImageView
typealias PlatformScrollView = UIScrollView
typealias PlatformTapGestureRecognizer = UITapGestureRecognizer
typealias PlatformLabel = UILabel
typealias PlatformLayoutPriority = UILayoutPriority
typealias PlatformViewBase = UIView
typealias PlatformTextViewDelegate = UITextViewDelegate

#elseif canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
typealias PlatformView = NSView
typealias PlatformStackView = NSStackView
typealias PlatformImage = NSImage
typealias PlatformImageView = NSImageView
typealias PlatformScrollView = NSScrollView
typealias PlatformTapGestureRecognizer = NSClickGestureRecognizer
typealias PlatformLabel = NSTextField
typealias PlatformLayoutPriority = NSLayoutConstraint.Priority
typealias PlatformViewBase = NSView
typealias PlatformTextViewDelegate = NSTextViewDelegate

// MARK: - Naming parity shims
//
// These exist purely so the rest of the module can write one line of code
// (`view.axis = .vertical`, `.label`, `.separator`, ...) instead of
// branching at every call site for a pure renaming difference. Anywhere the
// two frameworks differ in *behavior*, not just names, the call site branches
// explicitly instead — see MarkdownBlockViews.swift and
// MarkdownTextView+SwiftUI.swift for those.

extension NSStackView {
    /// AppKit calls this `orientation`; UIKit calls it `axis`. Same concept,
    /// same case names (`.horizontal` / `.vertical`).
    var axis: NSUserInterfaceLayoutOrientation {
        get { orientation }
        set { orientation = newValue }
    }
}

extension NSColor {
    // UIKit dropped the "Color" suffix from these semantic colors; AppKit
    // kept it. Re-exposing the short names here means the rest of the
    // module can use one spelling on both platforms. `public` because
    // these are used as default argument values in MarkdownStyle's public
    // initializer — same access-control rule as PlatformColor itself: a
    // public declaration can't default to an internal symbol.
    public static var label: NSColor { .labelColor }
    public static var secondaryLabel: NSColor { .secondaryLabelColor }
    public static var separator: NSColor { .separatorColor }

    // No 1:1 equivalents — these are judgment calls, not verified naming
    // parity. Reasonable adaptive (dark-mode-aware) picks, but worth a look
    // once you can see them rendered:
    public static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    public static var systemGray3: NSColor { .tertiaryLabelColor }
}

#endif

// MARK: - Stack view cross-axis fill, made explicit
//
// UIStackView's default alignment (`.fill`) stretches every arranged
// subview to match the stack's cross-axis size. NSStackView's default
// (`.gravityAreas`) does not, and its `.alignment` enum isn't a drop-in
// match for `.fill` semantics (it's `NSLayoutConstraint.Attribute`-based
// and axis-restricted). Rather than depend on either framework's exact
// default/enum behavior, every call site that needs cross-axis fill adds
// it explicitly via these two helpers — a no-op-but-harmless extra
// constraint on UIKit (same value the stack already computes), and the
// thing that actually makes it work on AppKit.

func addFullWidthArrangedSubview(_ view: PlatformView, to stack: PlatformStackView) {
    stack.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
}

func addFullHeightArrangedSubview(_ view: PlatformView, to stack: PlatformStackView) {
    stack.addArrangedSubview(view)
    view.heightAnchor.constraint(equalTo: stack.heightAnchor).isActive = true
}

// MARK: - Layer-backed appearance
//
// UIView.layer is non-optional (every UIView is layer-backed) and clipping
// is a plain `clipsToBounds` flag. NSView.layer is Optional and only exists
// once `wantsLayer = true` is set, and clipping is expressed via
// `layer.masksToBounds` rather than a view-level property. One call covers
// the "rounded card" look used by the code block, image preview, and table.

extension PlatformView {
    func applyCardAppearance(cornerRadius: CGFloat, borderColor: PlatformColor? = nil, borderWidth: CGFloat = 0) {
        #if canImport(UIKit)
        layer.cornerRadius = cornerRadius
        clipsToBounds = true
        if let borderColor {
            layer.borderColor = borderColor.cgColor
            layer.borderWidth = borderWidth
        }
        #elseif canImport(AppKit)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        if let borderColor {
            layer?.borderColor = borderColor.cgColor
            layer?.borderWidth = borderWidth
        }
        #endif
    }

    func applyBackgroundColor(_ color: PlatformColor) {
        #if canImport(UIKit)
        backgroundColor = color
        #elseif canImport(AppKit)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        #endif
    }
}
