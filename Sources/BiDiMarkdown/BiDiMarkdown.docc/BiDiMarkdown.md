# ``BiDiMarkdown``

A native SwiftUI Markdown renderer that gets bidirectional (mixed
Hebrew/Arabic and Latin-script) text right.

## Overview

Most Markdown renderers for SwiftUI assume left-to-right text. The moment a
document mixes Hebrew or Arabic with English — a chat message, a note, AI
output, a support ticket — headings misalign, list markers end up on the
wrong side, and punctuation lands next to the wrong word.

BiDiMarkdown resolves text direction independently for each block using the
Unicode first-strong-character rule, the same heuristic the Unicode
Bidirectional Algorithm itself uses to pick a paragraph's base direction.
It's a native renderer — UIKit on iOS, AppKit on macOS — wrapped in one
SwiftUI view, with no `WKWebView` and no external Markdown engine involved.

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

## Topics

### Essentials
- ``BiDiMarkdownView``
- ``MarkdownTextDirection``
- ``MarkdownStyle``
