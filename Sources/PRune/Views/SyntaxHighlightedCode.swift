import Foundation
import SwiftUI

struct SyntaxHighlightedCode: View {
    let source: String
    let emphasizedRanges: [Range<Int>]
    let emphasisColor: Color?
    let searchQuery: String

    init(
        source: String,
        emphasizedRanges: [Range<Int>] = [],
        emphasisColor: Color? = nil,
        searchQuery: String = ""
    ) {
        self.source = source
        self.emphasizedRanges = emphasizedRanges
        self.emphasisColor = emphasisColor
        self.searchQuery = searchQuery
    }

    var body: some View {
        Text(highlightedSource)
            .font(.system(size: 10.5, design: .monospaced))
            .lineLimit(nil)
            .lineSpacing(10)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .textSelection(.enabled)
    }

    private var highlightedSource: AttributedString {
        var highlighted = SyntaxHighlightCache.shared.attributedString(for: source)
        if let emphasisColor {
            for range in emphasizedRanges {
                guard
                    range.lowerBound >= 0,
                    range.upperBound <= highlighted.characters.count,
                    range.lowerBound < range.upperBound
                else { continue }
                let lowerBound = highlighted.characters.index(
                    highlighted.startIndex,
                    offsetBy: range.lowerBound
                )
                let upperBound = highlighted.characters.index(
                    highlighted.startIndex,
                    offsetBy: range.upperBound
                )
                highlighted[lowerBound..<upperBound].backgroundColor = emphasisColor
            }
        }
        return FindHighlight.apply(searchQuery, to: highlighted)
    }
}

@MainActor
private final class SyntaxHighlightCache {
    static let shared = SyntaxHighlightCache()

    private let maximumEntryCount = 12_000
    private let evictionCount = 3_000
    private var values: [String: AttributedString] = [:]
    private var insertionOrder: [String] = []

    func attributedString(for source: String) -> AttributedString {
        if let cached = values[source] {
            return cached
        }

        var highlighted = AttributedString(source)
        var offset = 0
        for token in SyntaxToken.tokenize(source) {
            let lowerBound = highlighted.characters.index(
                highlighted.startIndex,
                offsetBy: offset
            )
            offset += token.value.count
            let upperBound = highlighted.characters.index(
                highlighted.startIndex,
                offsetBy: offset
            )
            highlighted[lowerBound..<upperBound].foregroundColor = token.color
        }
        values[source] = highlighted
        insertionOrder.append(source)

        if values.count > maximumEntryCount {
            let expiredKeys = insertionOrder.prefix(evictionCount)
            for key in expiredKeys {
                values.removeValue(forKey: key)
            }
            insertionOrder.removeFirst(min(evictionCount, insertionOrder.count))
        }

        return highlighted
    }
}

private struct SyntaxToken {
    let value: String
    let kind: Kind

    enum Kind {
        case plain
        case keyword
        case literal
        case string
        case comment
        case punctuation
    }

    var color: Color {
        switch kind {
        case .plain:
            Color.white.opacity(0.78)
        case .keyword:
            Color(red: 0.78, green: 0.60, blue: 0.96)
        case .literal:
            Color(red: 0.94, green: 0.68, blue: 0.42)
        case .string:
            Color(red: 0.48, green: 0.84, blue: 0.68)
        case .comment:
            Color.white.opacity(0.38)
        case .punctuation:
            Color(red: 0.58, green: 0.72, blue: 0.86)
        }
    }

    static func tokenize(_ source: String) -> [SyntaxToken] {
        let characters = Array(source)
        var tokens: [SyntaxToken] = []
        var index = 0

        func isIdentifierStart(_ character: Character) -> Bool {
            character.isLetter || character == "_" || character == "$"
        }

        func isIdentifierPart(_ character: Character) -> Bool {
            isIdentifierStart(character) || character.isNumber
        }

        while index < characters.count {
            let character = characters[index]

            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                tokens.append(.init(value: String(characters[index...]), kind: .comment))
                break
            }

            if character == "\"" || character == "'" || character == "`" {
                let quote = character
                let start = index
                index += 1
                var isEscaped = false
                while index < characters.count {
                    let current = characters[index]
                    if current == quote, !isEscaped {
                        index += 1
                        break
                    }
                    if current == "\\" {
                        isEscaped.toggle()
                    } else {
                        isEscaped = false
                    }
                    index += 1
                }
                tokens.append(.init(value: String(characters[start..<index]), kind: .string))
                continue
            }

            if character.isNumber {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isNumber || ".xabcdefABCDEF_".contains(characters[index]) {
                    index += 1
                }
                tokens.append(.init(value: String(characters[start..<index]), kind: .literal))
                continue
            }

            if isIdentifierStart(character) {
                let start = index
                index += 1
                while index < characters.count, isIdentifierPart(characters[index]) {
                    index += 1
                }
                let word = String(characters[start..<index])
                let kind: Kind
                if keywords.contains(word) {
                    kind = .keyword
                } else if literals.contains(word) {
                    kind = .literal
                } else {
                    kind = .plain
                }
                tokens.append(.init(value: word, kind: kind))
                continue
            }

            let kind: Kind = "{}[]().,:;=<>+-*?!&|".contains(character) ? .punctuation : .plain
            tokens.append(.init(value: String(character), kind: kind))
            index += 1
        }

        return tokens
    }

    private static let keywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "default", "defer", "do", "else", "enum", "export", "extends", "final", "for", "from",
        "func", "function", "guard", "if", "implements", "import", "in", "interface", "let", "new",
        "override", "private", "protocol", "public", "repeat", "return", "static", "struct", "switch",
        "throw", "throws", "try", "typealias", "var", "while"
    ]

    private static let literals: Set<String> = [
        "false", "nil", "null", "true", "undefined"
    ]
}
