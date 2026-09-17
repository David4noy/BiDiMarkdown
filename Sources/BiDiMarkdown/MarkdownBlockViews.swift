//
//  MarkdownBlockViews.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Paragraph / heading / list-item / table-cell text

#if canImport(UIKit)
final class MarkdownParagraphTextView: UITextView {
    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        adjustsFontForContentSizeCategory = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
#elseif canImport(AppKit)
final class MarkdownParagraphTextView: NSTextView {
    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: Double.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Two genuinely different sizing needs share this class: a wrapping
    /// paragraph wants NO intrinsic width (width comes from constraints,
    /// height is computed by wrapping at that width) — but a table cell
    /// wants the opposite: a real, content-driven intrinsic width, so the
    /// table's row stack can size each column to its content instead of
    /// wrapping or collapsing it. Reporting `noIntrinsicMetric` width
    /// unconditionally (as this used to) is correct for paragraphs but
    /// starves a stack view's `.fill` distribution of the one signal it
    /// needs to size table columns — that's what made the table render at
    /// some seemingly-fixed size instead of fitting its content.
    enum SizingMode: Equatable {
        case wrapsToContainerWidth
        case intrinsicSize
    }

    var sizingMode: SizingMode = .wrapsToContainerWidth {
        didSet {
            guard sizingMode != oldValue else { return }
            if sizingMode == .intrinsicSize {
                textContainer?.widthTracksTextView = false
                textContainer?.containerSize = NSSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
            } else {
                textContainer?.widthTracksTextView = true
            }
            invalidateIntrinsicContentSize()
        }
    }

    /// UITextView exposes `.attributedText`; NSTextView only exposes text
    /// through `.textStorage`. This shim lets every other file in the
    /// module write `view.attributedText = ...` unchanged on both platforms.
    var attributedText: NSAttributedString? {
        get { textStorage.map { NSAttributedString(attributedString: $0) } }
        set {
            textStorage?.setAttributedString(newValue ?? NSAttributedString())
            invalidateIntrinsicContentSize()
        }
    }

    /// UITextView calls this `.textAlignment`; NSTextView calls it `.alignment`.
    var textAlignment: NSTextAlignment {
        get { alignment }
        set { alignment = newValue }
    }

    /// NSTextView has no usable `intrinsicContentSize` out of the box —
    /// unlike UITextView, it only reliably participates in Auto Layout when
    /// embedded in an NSScrollView. This is a well-documented AppKit gap
    /// (see e.g. the ModernAppKit / AutoLayoutTextView open-source projects
    /// built specifically to patch it). Patched the same way here: compute
    /// size from the layout manager's used rect, and invalidate whenever
    /// the assigned width actually changes (wrapsToContainerWidth mode) so
    /// wrapping gets recalculated at the new width.
    ///
    /// UNVERIFIED ON A REAL BUILD — this is the single highest-risk piece of
    /// the macOS port. If paragraph text doesn't wrap/size correctly, or a
    /// table column doesn't size to its content, look here first.
    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let extraWidth = textContainerInset.width * 2
        let extraHeight = textContainerInset.height * 2
        switch sizingMode {
        case .wrapsToContainerWidth:
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height) + extraHeight)
        case .intrinsicSize:
            return NSSize(width: ceil(used.width) + extraWidth, height: ceil(used.height) + extraHeight)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if sizingMode == .wrapsToContainerWidth, abs(oldWidth - newSize.width) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }
}
#endif

// MARK: - Code block

protocol MarkdownCodeBlockViewDelegate: AnyObject {
    func markdownCodeBlockView(_ view: MarkdownCodeBlockView, didTapCopy code: String)
}

final class MarkdownCodeBlockView: PlatformView {
    weak var delegate: MarkdownCodeBlockViewDelegate?
    private let code: String
    #if canImport(UIKit)
    private var copyButton: UIButton!
    #elseif canImport(AppKit)
    private var copyButton: NSButton!
    #endif

    init(code: String, language: String?, style: MarkdownStyle) {
        self.code = code
        super.init(frame: .zero)
        setup(language: language, style: style)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup(language: String?, style: MarkdownStyle) {
        applyCardAppearance(cornerRadius: 8)
        applyBackgroundColor(style.codeBackgroundColor)

        let languageLabel = PlatformLabel()
        #if canImport(UIKit)
        languageLabel.text = language ?? "text"
        languageLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        languageLabel.textColor = .secondaryLabel
        #elseif canImport(AppKit)
        languageLabel.stringValue = language ?? "text"
        languageLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        languageLabel.textColor = .secondaryLabel
        languageLabel.isEditable = false
        languageLabel.isBordered = false
        languageLabel.drawsBackground = false
        #endif
        languageLabel.translatesAutoresizingMaskIntoConstraints = false

        #if canImport(UIKit)
        let copyButton = UIButton(type: .system)
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = .secondaryLabel
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        #elseif canImport(AppKit)
        let copyButton = NSButton(
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: #selector(copyTapped)
        )
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .secondaryLabel
        #endif
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        self.copyButton = copyButton
        addSubview(languageLabel)
        addSubview(copyButton)

        // Code content is a plain label, not MarkdownParagraphTextView: it's
        // deliberately non-wrapping (byClipping) and lives inside its own
        // horizontally-scrolling container, which is a different sizing
        // model than the wrap-to-container-width paragraphs elsewhere.
        // Always LTR regardless of document direction — forced via the
        // writingDirection *attribute* (system bidi override), never by
        // altering the string.
        let codeLabel = PlatformLabel()
        let embedLTR = NSNumber(value: NSWritingDirection.leftToRight.rawValue | NSWritingDirectionFormatType.embedding.rawValue)
        let codeAttrString = NSAttributedString(string: code, attributes: [
            .font: MarkdownFonts.code(style.codeFontSize),
            .foregroundColor: style.codeTextColor,
            .writingDirection: [embedLTR]
        ])
        #if canImport(UIKit)
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        codeLabel.textAlignment = .left
        codeLabel.attributedText = codeAttrString
        #elseif canImport(AppKit)
        codeLabel.isEditable = false
        codeLabel.isBordered = false
        codeLabel.drawsBackground = false
        codeLabel.lineBreakMode = .byClipping
        codeLabel.alignment = .left
        codeLabel.maximumNumberOfLines = 0
        codeLabel.attributedStringValue = codeAttrString
        #endif

        let measuredHeight = ceil((code as NSString).boundingRect(
            with: CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: MarkdownFonts.code(style.codeFontSize)],
            context: nil
        ).height)

        let scrollView = PlatformScrollView()
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        #if canImport(UIKit)
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(codeLabel)
        NSLayoutConstraint.activate([
            codeLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            codeLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -10),
            codeLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            codeLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            codeLabel.heightAnchor.constraint(equalToConstant: measuredHeight)
        ])
        #elseif canImport(AppKit)
        // UNVERIFIED ON A REAL BUILD. NSScrollView needs an explicit
        // `documentView` (UIScrollView has no equivalent concept — a plain
        // subview is enough there). Deliberately no trailing-edge pin here:
        // unlike UIScrollView, the documentView must be free to be *wider*
        // than the visible clip view for horizontal scrolling to do
        // anything — pinning both edges would clamp it to the viewport
        // width and defeat the scroller entirely.
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = codeLabel
        NSLayoutConstraint.activate([
            codeLabel.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor, constant: 10),
            codeLabel.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor, constant: -10),
            codeLabel.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor, constant: 12),
            codeLabel.heightAnchor.constraint(equalToConstant: measuredHeight)
        ])
        #endif
        scrollView.heightAnchor.constraint(equalToConstant: measuredHeight + 20).isActive = true

        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            languageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            languageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            copyButton.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            copyButton.leadingAnchor.constraint(greaterThanOrEqualTo: languageLabel.trailingAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func copyTapped() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        copyButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        }
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        }
        #endif
        delegate?.markdownCodeBlockView(self, didTapCopy: code)
    }
}

// MARK: - Blockquote

final class MarkdownBlockquoteView: PlatformView {
    init(childViews: [PlatformView], direction: MarkdownTextDirection, style: MarkdownStyle, sampleText: String) {
        super.init(frame: .zero)
        let resolved = MarkdownDirectionResolver.resolvedDirection(for: direction, sampleText: sampleText)
        let isRTL = resolved == .rightToLeft

        let bar = PlatformView()
        bar.applyBackgroundColor(style.quoteBarColor)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 3).isActive = true

        let content = PlatformStackView()
        content.axis = .vertical
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        for child in childViews {
            addFullWidthArrangedSubview(child, to: content)
        }

        addSubview(bar)
        addSubview(content)

        // No UIStackView/NSStackView wrapping [bar, content] here on
        // purpose. With a multi-block quote (more than one paragraph, or a
        // paragraph plus a nested list) a stack view's fill distribution has
        // to *infer* content's share of the row width from hugging/
        // compression priorities alone — and that inference silently breaks
        // down for multi-child content, leaving `content` with an
        // ill-defined width. Since content's own children stack vertically,
        // an ill-defined width makes them collapse on top of each other
        // instead of stacking. Pinning both of content's horizontal edges
        // explicitly (below) removes that inference step entirely — and
        // conveniently, plain leading/trailing/top/bottom anchor
        // constraints work identically on UIKit and AppKit, so this part of
        // the fix needed zero platform-specific code.
        var constraints = [
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        if isRTL {
            constraints += [
                bar.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: bar.leadingAnchor, constant: -10)
            ]
        } else {
            constraints += [
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10)
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - List item row

final class MarkdownListItemRowView: PlatformView {
    init(markerText: String, contentView: PlatformView, direction: MarkdownTextDirection, style: MarkdownStyle, sampleText: String, taskChecked: Bool? = nil) {
        super.init(frame: .zero)
        let resolved = MarkdownDirectionResolver.resolvedDirection(for: direction, sampleText: sampleText)
        let isRTL = resolved == .rightToLeft

        let marker = PlatformLabel()
        #if canImport(UIKit)
        marker.text = markerText
        marker.font = MarkdownFonts.body(style.bodyFontSize)
        marker.textColor = style.textColor
        if let taskChecked {
            // VoiceOver reads "☑"/"☐" as "ballot box with check"/"ballot
            // box" by default, which is accurate but not as clear as
            // stating the state directly.
            marker.isAccessibilityElement = true
            marker.accessibilityLabel = taskChecked ? "Checked" : "Not checked"
        }
        #elseif canImport(AppKit)
        marker.stringValue = markerText
        marker.font = MarkdownFonts.body(style.bodyFontSize)
        marker.textColor = style.textColor
        marker.isEditable = false
        marker.isBordered = false
        marker.drawsBackground = false
        if let taskChecked {
            marker.setAccessibilityLabel(taskChecked ? "Checked" : "Not checked")
        }
        #endif
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.setContentHuggingPriority(.required, for: .horizontal)
        marker.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(marker)
        addSubview(contentView)

        // Same reasoning as MarkdownBlockquoteView: no stack view for this
        // row. A list item's contentView is often multi-block (a paragraph
        // plus a nested list, for example), and a stack view's fill
        // distribution can't reliably infer that content's width share from
        // hugging priorities alone in that case — it silently ends up
        // ill-defined, and content's own vertically-stacked children then
        // collapse on top of each other. Pinning both of content's
        // horizontal edges explicitly removes the inference step entirely.
        var constraints = [
            marker.topAnchor.constraint(equalTo: topAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            marker.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ]
        if isRTL {
            constraints += [
                marker.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: marker.leadingAnchor, constant: -8)
            ]
        } else {
            constraints += [
                marker.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentView.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 8)
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Image preview

protocol MarkdownImageViewDelegate: AnyObject {
    func markdownImageView(_ view: MarkdownImageView, didTap url: URL)
}

final class MarkdownImageView: PlatformView {
    weak var delegate: MarkdownImageViewDelegate?
    private let imageView = PlatformImageView()
    private let altLabel = PlatformLabel()
    #if canImport(UIKit)
    private let spinner = UIActivityIndicatorView(style: .medium)
    #elseif canImport(AppKit)
    private let spinner = NSProgressIndicator()
    #endif
    private var task: URLSessionDataTask?
    private let sourceURL: URL?
    private var heightConstraint: NSLayoutConstraint!

    init(alt: String, urlString: String, style: MarkdownStyle) {
        self.sourceURL = URL(string: urlString)
        super.init(frame: .zero)
        applyCardAppearance(cornerRadius: 8)
        applyBackgroundColor(.secondarySystemBackground)

        #if canImport(UIKit)
        imageView.contentMode = .scaleAspectFit
        #elseif canImport(AppKit)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        #endif
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        #if canImport(UIKit)
        altLabel.text = alt
        altLabel.font = .systemFont(ofSize: 13)
        altLabel.textColor = .secondaryLabel
        altLabel.textAlignment = .center
        #elseif canImport(AppKit)
        altLabel.stringValue = alt
        altLabel.font = .systemFont(ofSize: 13)
        altLabel.textColor = .secondaryLabel
        altLabel.alignment = .center
        altLabel.isEditable = false
        altLabel.isBordered = false
        altLabel.drawsBackground = false
        #endif
        altLabel.translatesAutoresizingMaskIntoConstraints = false
        altLabel.isHidden = true

        #if canImport(AppKit)
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        #endif
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        addSubview(altLabel)

        heightConstraint = heightAnchor.constraint(equalToConstant: 160)
        NSLayoutConstraint.activate([
            heightConstraint,
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            altLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            altLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        addGestureRecognizer(PlatformTapGestureRecognizer(target: self, action: #selector(tapped)))
        #if canImport(UIKit)
        isUserInteractionEnabled = true
        spinner.startAnimating()
        #elseif canImport(AppKit)
        spinner.startAnimation(nil)
        #endif
        load()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func load() {
        guard let sourceURL else { stopSpinner(); altLabel.isHidden = false; return }
        task = URLSession.shared.dataTask(with: sourceURL) { [weak self] data, _, _ in
            guard let self, let data, let image = PlatformImage(data: data) else {
                DispatchQueue.main.async { self?.stopSpinner(); self?.altLabel.isHidden = false }
                return
            }
            DispatchQueue.main.async {
                self.stopSpinner()
                self.imageView.image = image
                let ratio = image.size.height / max(image.size.width, 1)
                self.heightConstraint.constant = min(300, max(120, self.bounds.width * ratio))
            }
        }
        task?.resume()
    }

    private func stopSpinner() {
        #if canImport(UIKit)
        spinner.stopAnimating()
        #elseif canImport(AppKit)
        spinner.stopAnimation(nil)
        #endif
    }

    @objc private func tapped() {
        guard let sourceURL else { return }
        delegate?.markdownImageView(self, didTap: sourceURL)
    }

    deinit { task?.cancel() }
}

// MARK: - Horizontal rule

final class MarkdownHorizontalRuleView: PlatformView {
    init() {
        super.init(frame: .zero)
        applyBackgroundColor(.separator)
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}
