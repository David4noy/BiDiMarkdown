# Changelog

## Unreleased

- Autolinking of bare URLs (`https://...`, `www...`) — on by default, toggle
  via the new `autolinkPlainURLs` parameter.
- HTML entity decoding: common named entities (`&amp;`, `&nbsp;`, …) and any
  numeric reference (`&#39;`, `&#x27;`).
- RTL tables now start scrolled to the correct (trailing) edge when wider
  than their container, instead of always opening at the physical-left edge.
- Accessibility: task-list checkboxes now expose a "Checked"/"Not checked"
  label to VoiceOver instead of relying on the default glyph pronunciation.
- Checked task items now render with strikethrough on their own text.
- Fixed: a link/image title (`[text](url "title")`) was being concatenated
  into the URL string, which silently broke the link (`URL(string:)` fails
  on a string containing a literal space and quotes). Titles are now
  parsed and dropped (not rendered — there's no tooltip concept here); the
  URL itself is no longer corrupted.
- Mac Catalyst support restored alongside native macOS (reuses the UIKit
  render path unchanged — useful if you already have a Catalyst-based Mac
  app and don't want to add an AppKit target just for this).


## 1.0.0

Initial release.

- Bidi-aware Markdown rendering (`.auto`, `.rtl`, `.ltr`) for SwiftUI.
- Headings, paragraphs, bold/italic/bold-italic, strikethrough, inline code,
  fenced code blocks with a copy button, links, async-loaded images,
  ordered/unordered/nested lists, blockquotes, tables with column alignment,
  horizontal rules.
- Native rendering: UIKit on iOS, AppKit on macOS — no WKWebView.
- Public API: `BiDiMarkdownView`, `MarkdownTextDirection`, `MarkdownStyle`.
- DocC documentation catalog.

- Task list support (`- [ ]` / `- [x]`) — renders as a checkbox marker
  (☐ / ☑), read-only (matches how most rendered Markdown views work; the
  raw source is still where you'd toggle one). Plain bullets and checkbox
  items can be mixed freely within the same list.
