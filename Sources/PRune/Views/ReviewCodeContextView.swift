import AppKit
import SwiftUI

struct ReviewCodeContextView: View {
    let comment: PullRequestComment
    let onOpenCode: (String, Int?, String?) -> Void
    @State private var isFileLinkHovered = false

    private var parsedLines: [ReviewCodeLine] {
        ReviewCodeLine.parse(
            comment.diffHunk ?? "",
            targetLine: comment.line,
            targetSide: comment.diffSide
        )
    }

    private var snippet: ReviewCodeSnippet {
        ReviewCodeSnippet(lines: parsedLines, maximumVisibleLines: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let path = comment.path {
                    Button {
                        onOpenCode(path, comment.line, comment.diffSide)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(isFileLinkHovered ? Color.accentColor : Color.mutedText)
                            Text(path)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(isFileLinkHovered ? Color.accentColor : Color.primary)
                                .underline(isFileLinkHovered, color: Color.accentColor.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(isFileLinkHovered ? Color.accentColor : Color.mutedText)
                        }
                        .padding(.horizontal, 7)
                        .frame(minHeight: 25)
                        .background(isFileLinkHovered ? Color.accentColor.opacity(0.11) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isFileLinkHovered ? Color.accentColor.opacity(0.34) : .clear,
                                    lineWidth: 0.8
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        withAnimation(.easeOut(duration: 0.12)) {
                            isFileLinkHovered = isHovering
                        }
                        if isHovering {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    .help("Show this file in Code")
                } else {
                    Label("Reviewed code", systemImage: "doc.text")
                        .font(.system(size: 10.5, weight: .medium))
                }

                if comment.isOutdated {
                    Text("Outdated")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }

                Spacer()

                if let line = comment.line {
                    Text("L\(line)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.mutedText)
                }
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(Color.elevatedBackground)

            if snippet.lines.isEmpty {
                Text("Code context is no longer available in this diff.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.mutedText)
                    .padding(11)
            } else {
                if snippet.hiddenBefore > 0 {
                    hiddenLinesRow(count: snippet.hiddenBefore)
                }
                ForEach(snippet.lines) { line in
                    codeLine(line)
                }
                if snippet.hiddenAfter > 0 {
                    hiddenLinesRow(count: snippet.hiddenAfter)
                }
            }
        }
        .background(Color.appBackground.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(comment.isOutdated ? Color.white.opacity(0.10) : Color.blue.opacity(0.34))
        )
    }

    private func codeLine(_ line: ReviewCodeLine) -> some View {
        HStack(spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 34, alignment: .trailing)
                .foregroundStyle(Color.white.opacity(0.28))
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 34, alignment: .trailing)
                .foregroundStyle(Color.white.opacity(0.28))
            Text(marker(for: line.kind))
                .frame(width: 22, alignment: .center)
                .foregroundStyle(markerColor(for: line.kind))
            SyntaxHighlightedCode(source: line.content.isEmpty ? " " : line.content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(minHeight: 23)
        .background(line.isTarget ? Color(red: 0.23, green: 0.39, blue: 0.53).opacity(0.88) : background(for: line.kind))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(line.isTarget ? Color.blue.opacity(0.9) : accent(for: line.kind))
                .frame(width: 3)
        }
    }

    private func hiddenLinesRow(count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "ellipsis")
                .font(.system(size: 9, weight: .semibold))
            Text("\(count) lines hidden")
                .font(.system(size: 9.5, design: .monospaced))
        }
        .foregroundStyle(Color.mutedText)
        .padding(.leading, 13)
        .frame(maxWidth: .infinity, minHeight: 21, alignment: .leading)
        .background(Color.white.opacity(0.025))
    }

    private func marker(for kind: DiffLineKind) -> String {
        switch kind {
        case .context: " "
        case .addition: "+"
        case .deletion: "−"
        }
    }

    private func markerColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: Color.mutedText
        case .addition: Color.green.opacity(0.76)
        case .deletion: Color.red.opacity(0.76)
        }
    }

    private func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: .clear
        case .addition: Color(red: 0.12, green: 0.25, blue: 0.16).opacity(0.82)
        case .deletion: Color(red: 0.28, green: 0.12, blue: 0.14).opacity(0.80)
        }
    }

    private func accent(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: .clear
        case .addition: Color.green.opacity(0.72)
        case .deletion: Color.red.opacity(0.72)
        }
    }
}

private struct ReviewCodeSnippet {
    let lines: [ReviewCodeLine]
    let hiddenBefore: Int
    let hiddenAfter: Int

    init(lines: [ReviewCodeLine], maximumVisibleLines: Int) {
        guard lines.count > maximumVisibleLines else {
            self.lines = lines
            hiddenBefore = 0
            hiddenAfter = 0
            return
        }

        let targetIndex = lines.firstIndex(where: \.isTarget)
            ?? lines.lastIndex(where: { line in
                switch line.kind {
                case .addition, .deletion: true
                case .context: false
                }
            })
            ?? lines.index(before: lines.endIndex)
        let leadingContext = maximumVisibleLines / 2
        var lowerBound = max(lines.startIndex, targetIndex - leadingContext)
        var upperBound = min(lines.endIndex, lowerBound + maximumVisibleLines)
        lowerBound = max(lines.startIndex, upperBound - maximumVisibleLines)
        upperBound = min(lines.endIndex, lowerBound + maximumVisibleLines)

        self.lines = Array(lines[lowerBound..<upperBound])
        hiddenBefore = lowerBound
        hiddenAfter = lines.count - upperBound
    }
}

private struct ReviewCodeLine: Identifiable {
    let id: Int
    let kind: DiffLineKind
    let oldLine: Int?
    let newLine: Int?
    let content: String
    let isTarget: Bool

    static func parse(
        _ hunk: String,
        targetLine: Int?,
        targetSide: String?
    ) -> [ReviewCodeLine] {
        let rawLines = hunk
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let header = rawLines.first, header.hasPrefix("@@ ") else { return [] }

        let ranges = header.split(separator: " ")
        var oldLine = ranges.count > 1 ? rangeStart(ranges[1]) : 0
        var newLine = ranges.count > 2 ? rangeStart(ranges[2]) : 0
        var result: [ReviewCodeLine] = []

        for (index, rawLine) in rawLines.dropFirst().enumerated() {
            guard let prefix = rawLine.first, prefix != "\\" else { continue }
            let kind: DiffLineKind
            let displayedOldLine: Int?
            let displayedNewLine: Int?

            switch prefix {
            case "+":
                kind = .addition
                displayedOldLine = nil
                displayedNewLine = newLine
                newLine += 1
            case "-":
                kind = .deletion
                displayedOldLine = oldLine
                displayedNewLine = nil
                oldLine += 1
            case " ":
                kind = .context
                displayedOldLine = oldLine
                displayedNewLine = newLine
                oldLine += 1
                newLine += 1
            default:
                continue
            }

            let usesLeftSide = targetSide?.uppercased() == "LEFT"
            let isTarget = targetLine.map { target in
                usesLeftSide ? displayedOldLine == target : displayedNewLine == target
            } ?? false
            result.append(
                ReviewCodeLine(
                    id: index,
                    kind: kind,
                    oldLine: displayedOldLine,
                    newLine: displayedNewLine,
                    content: String(rawLine.dropFirst()),
                    isTarget: isTarget
                )
            )
        }

        return result
    }

    private static func rangeStart(_ value: Substring) -> Int {
        Int(value.dropFirst().split(separator: ",").first ?? "0") ?? 0
    }
}
