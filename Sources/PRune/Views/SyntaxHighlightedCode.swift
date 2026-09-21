import SwiftUI

struct SyntaxHighlightedCode: View {
    let source: String

    var body: some View {
        SyntaxHighlightCache.shared.text(for: source)
            .font(.system(size: 10.5, design: .monospaced))
            .lineLimit(nil)
            .lineSpacing(10)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .textSelection(.enabled)
    }
}

@MainActor
private final class SyntaxHighlightCache {
    static let shared = SyntaxHighlightCache()

    private let maximumEntryCount = 12_000
    private let evictionCount = 3_000
    private var values: [String: Text] = [:]
    private var insertionOrder: [String] = []

    func text(for source: String) -> Text {
        if let cached = values[source] {
            return cached
        }

        let highlighted = SyntaxToken.tokenize(source).reduce(Text("")) { result, token in
            result + Text(token.value).foregroundColor(token.color)
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
