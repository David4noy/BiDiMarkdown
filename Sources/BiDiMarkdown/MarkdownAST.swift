//
//  MarkdownAST.swift
//  BiDiMarkdown
//
//  Created by David Noy on 07/08/2026.
//

import Foundation

indirect enum MarkdownBlockNode {
    case heading(level: Int, inline: [MarkdownInlineNode])
    case paragraph([MarkdownInlineNode])
    case codeBlock(language: String?, code: String)
    case blockQuote([MarkdownBlockNode])
    case unorderedList(items: [[MarkdownBlockNode]], checked: [Bool?], tight: Bool)
    case orderedList(start: Int, items: [[MarkdownBlockNode]], tight: Bool)
    case table(alignments: [MarkdownTableAlignment], header: [[MarkdownInlineNode]], rows: [[[MarkdownInlineNode]]])
    case image(alt: String, url: String)
    case horizontalRule
}

enum MarkdownTableAlignment { case left, center, right, none }

indirect enum MarkdownInlineNode {
    case text(String)
    case bold([MarkdownInlineNode])
    case italic([MarkdownInlineNode])
    case boldItalic([MarkdownInlineNode])
    case strikethrough([MarkdownInlineNode])
    case code(String)
    case link(text: [MarkdownInlineNode], url: String)
    case image(alt: String, url: String)
}
