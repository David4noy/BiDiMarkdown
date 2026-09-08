# BiDiMarkdown

**A native SwiftUI Markdown renderer that gets bidirectional text right.**

![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20Mac%20Catalyst%2016%2B-blue)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Most Markdown renderers for SwiftUI assume left-to-right text. The moment a
document mixes Hebrew or Arabic with English — a chat message, a note, AI
output, a support ticket — headings misalign, list markers end up on the
wrong side, and punctuation lands next to the wrong word. BiDiMarkdown is a
Markdown renderer built specifically to handle that: it resolves text
direction per block using the Unicode first-strong-character rule, and lets
you force LTR or RTL when you need to.

It's implemented as a lightweight native renderer (UIKit on iOS, AppKit on
macOS) wrapped in a single SwiftUI `View` — no `WKWebView`, no JavaScript,
no external Markdown engine, and no Mac Catalyst: macOS gets a real AppKit
render path, not a repackaged iOS one.

> **macOS support is new and not yet verified against a real build** — I
> don't have a way to compile and run AppKit code in the environment this
> was written in. The riskiest spots (NSTextView's Auto Layout sizing,
> NSScrollView's `documentView` setup, a couple of semantic color choices)
> are flagged with `UNVERIFIED ON A REAL BUILD` comments right at the code
> that needs a look. iOS is unaffected by any of this — nothing there
> changed as part of adding macOS support.

## Why not just use `Text(markdown:)` or MarkdownUI?

- SwiftUI's built-in Markdown support in `Text` only handles inline styling
  (bold, italic, links) — no tables, no code blocks, no block-level layout,
  and no direction control.
- General-purpose libraries like [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)
  are excellent for LTR content, but don't reason about per-block text
  direction — a Hebrew/English mixed document will render with every block
  pinned to the same direction, and list/quote markers on the wrong side.
- BiDiMarkdown trades some of that general-purpose surface for one thing
  done specifically: correct mixed-direction rendering, with `.auto`,
  `.rtl`, and `.ltr` modes you can toggle per view.

## Features

- **Bidi-aware by default** — `.auto` mode resolves LTR/RTL per block from
  its own content, so a single document can mix English paragraphs with
  Hebrew or Arabic ones correctly.
- **GitHub-flavored-ish Markdown**: headings, paragraphs, bold/italic/
  bold-italic, strikethrough, inline code, fenced code blocks (with a copy
  button), links, images (loaded asynchronously), ordered/unordered lists
  (with nesting), task lists (`- [ ]`/`- [x]`), blockquotes, tables, and
  horizontal rules.
- **Native rendering** — built on `UIStackView`/`UITextView`, not an
  embedded web view. No JavaScript bridge, no CDN dependency, no WKWebView
  memory overhead.
- **Customizable** via `MarkdownStyle` — colors, font sizes.
- **SwiftUI-first API** — one `View`, `BiDiMarkdownView`, that's `Equatable`-
  safe and doesn't rebuild its content on every unrelated re-render.
- **iOS and native macOS** — separate UIKit and AppKit render paths behind
  one API, not an iOS app repackaged via Catalyst. (Catalyst itself is also
  supported, for apps already built that way — it reuses the UIKit path
  unchanged.)

## Requirements

- Swift 5.9+
- iOS 16.0+, macOS 13.0+, or Mac Catalyst 16.0+
- SwiftUI

## Installation

### Xcode

File → Add Package Dependencies… and enter the repository URL:

```
https://github.com/David4noy/BiDiMarkdown.git
```

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/David4noy/BiDiMarkdown.git", from: "1.0.0")
],
targets: [
    .target(name: "YourTarget", dependencies: ["BiDiMarkdown"])
]
```

## Usage

### Basic

```swift
import SwiftUI
import BiDiMarkdown

struct ContentView: View {
    let markdown = """
    # שלום, World

    This paragraph is English. זו פסקה בעברית.

    - פריט ראשון
    - Second item
    """

    var body: some View {
        ScrollView {
            BiDiMarkdownView(markdown: markdown)
                .padding()
        }
    }
}
```

### Explicit direction

```swift
BiDiMarkdownView(markdown: text, direction: .rtl)   // force RTL
BiDiMarkdownView(markdown: text, direction: .ltr)   // force LTR
BiDiMarkdownView(markdown: text, direction: .auto)  // default — resolve per block
```

### Autolinking bare URLs

On by default — a URL typed without `[text](url)` syntax (`https://example.com`,
`www.example.com`) still becomes a tappable link. Turn it off if you only
want explicit Markdown links to be tappable:

```swift
BiDiMarkdownView(markdown: text, autolinkPlainURLs: false)
```

### Styling

```swift
BiDiMarkdownView(
    markdown: text,
    style: MarkdownStyle(
        linkColor: .systemPurple,
        codeBackgroundColor: .black.withAlphaComponent(0.05),
        bodyFontSize: 15
    )
)
```

### Handling link taps

```swift
BiDiMarkdownView(markdown: text) { url in
    #if canImport(UIKit)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}
```

## Supported syntax

| Syntax | Supported |
|---|---|
| Headings (`#` – `######`) | ✅ |
| Bold / italic / bold-italic | ✅ |
| Strikethrough (`~~text~~`) | ✅ |
| Inline code / fenced code blocks | ✅ |
| Links `[text](url)` | ✅ |
| Bare URL autolinking (`https://...`, `www...`) | ✅ (toggle: `autolinkPlainURLs`) |
| HTML entities (`&amp;`, `&#39;`, …) | ✅ (common named entities + any numeric reference) |
| Images `![alt](url)` | ✅ (async-loaded) |
| Ordered / unordered lists, nested | ✅ |
| Blockquotes, including multi-paragraph | ✅ |
| Tables with column alignment | ✅ |
| Horizontal rules | ✅ |
| Task lists (`- [ ]` / `- [x]`) | ✅ |
| HTML passthrough | ❌ (by design — this is a native renderer, not an HTML engine) |

## How direction resolution works

For `.auto`, each block (and, separately, each table cell) is scanned for
its first "strong" character — a letter that unambiguously belongs to a
left-to-right or right-to-left script (Hebrew and Arabic blocks count as
strong-RTL). That's the same first-strong-character heuristic the Unicode
Bidirectional Algorithm uses to establish a paragraph's base direction. The
result decides:

- The paragraph's base writing direction and alignment.
- Which side a list marker or blockquote bar renders on.
- Column order in tables.

Inline runs within a paragraph (a Hebrew sentence with an English word in
the middle) are left to the platform's own text layout engine via
`NSParagraphStyle.baseWritingDirection = .natural`, which applies the full
Unicode Bidi Algorithm — BiDiMarkdown does not re-implement inline
reordering itself.

## Architecture

```
Markdown string
      │
      ▼
MarkdownParser (block-level)  →  MarkdownInlineScanner (inline-level)
      │
      ▼
   [MarkdownBlockNode]  (AST)
      │
      ▼
MarkdownView (UIKit or AppKit)  →  builds one stack/text/image view per block
      │
      ▼
BiDiMarkdownView (SwiftUI)  →  wraps it all in a single public View
```

Only `BiDiMarkdownView`, `MarkdownTextDirection`, and `MarkdownStyle` are
public — the parser, AST, and view internals are free to change without
breaking consumers.

## Documentation

The public API (`BiDiMarkdownView`, `MarkdownTextDirection`, `MarkdownStyle`)
is documented with DocC comments, and the package ships a DocC catalog
(`Sources/BiDiMarkdown/BiDiMarkdown.docc`). Once this is on GitHub with
tagged releases, [Swift Package Index](https://swiftpackageindex.com) picks
this up automatically and renders it. To build it yourself:

- **Xcode**: Product → Build Documentation.
- **Command line**: `swift package generate-documentation` (needs the
  `swift-docc-plugin` dependency already declared in `Package.swift`).

## Contributing

Issues and pull requests are welcome. Please include a minimal Markdown
sample that reproduces any rendering bug — direction bugs in particular are
much easier to fix with the exact input that triggers them.

## License

MIT — see [LICENSE](LICENSE).
