import SwiftUI

struct MarkdownDocumentView: View {
    let markdown: String
    var searchQuery = ""

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(.system(size: level == 1 ? 17 : level == 2 ? 14 : 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.top, level == 1 ? 4 : 1)
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.76))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 4, height: 4)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
            .padding(.leading, 3)
        case let .task(done, text):
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(done ? Color.green.opacity(0.9) : .clear)
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(done ? Color.green.opacity(0.9) : Color.white.opacity(0.28), lineWidth: 1)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.appBackground)
                    }
                }
                .frame(width: 13, height: 13)
                .padding(.top, 1)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(done ? 0.48 : 0.76))
                    .strikethrough(done, color: Color.white.opacity(0.35))
            }
        case let .quote(text):
            Text(inlineMarkdown(text))
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
                .padding(.leading, 11)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 3)
                }
        case let .code(language, code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(Color.mutedText)
                }
                Text(FindHighlight.apply(searchQuery, to: AttributedString(code)))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .textSelection(.enabled)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.subtleBorder))
        case .divider:
            Divider().overlay(Color.subtleBorder)
        }
    }

    private func inlineMarkdown(_ value: String) -> AttributedString {
        let rendered = (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
        return FindHighlight.apply(searchQuery, to: rendered)
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case task(done: Bool, text: String)
    case quote(String)
    case code(language: String?, code: String)
    case divider

    static func parse(_ source: String) -> [MarkdownBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let cleaned = normalized.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInCodeBlock = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    codeLines = []
                    codeLanguage = nil
                    isInCodeBlock = false
                } else {
                    flushParagraph()
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    isInCodeBlock = true
                }
                continue
            }

            if isInCodeBlock {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            let hashCount = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashCount), trimmed.dropFirst(hashCount).first == " " {
                flushParagraph()
                blocks.append(.heading(
                    level: hashCount,
                    text: String(trimmed.dropFirst(hashCount + 1))
                ))
                continue
            }

            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                flushParagraph()
                blocks.append(.task(
                    done: trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]"),
                    text: String(trimmed.dropFirst(6))
                ))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
                continue
            }

            paragraph.append(trimmed)
        }

        if isInCodeBlock {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return blocks
    }
}
