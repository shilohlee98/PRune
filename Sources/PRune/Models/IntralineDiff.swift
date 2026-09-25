struct IntralineDiffHighlights: Equatable, Hashable, Sendable {
    static let empty = IntralineDiffHighlights(old: [], new: [])

    let old: [Range<Int>]
    let new: [Range<Int>]
}

enum IntralineDiff {
    private enum TokenKind {
        case word
        case whitespace
        case punctuation
    }

    private struct Token {
        let value: String
        let range: Range<Int>
    }

    private static let maximumMatrixCellCount = 40_000

    static func highlights(from oldSource: String, to newSource: String) -> IntralineDiffHighlights {
        guard oldSource != newSource else { return .empty }

        let oldTokens = tokens(in: oldSource)
        let newTokens = tokens(in: newSource)
        let matrixCellCount = oldTokens.count.multipliedReportingOverflow(by: newTokens.count)
        guard !matrixCellCount.overflow, matrixCellCount.partialValue <= maximumMatrixCellCount else {
            return fallbackHighlights(from: oldSource, to: newSource)
        }

        var lengths = Array(
            repeating: Array(repeating: 0, count: newTokens.count + 1),
            count: oldTokens.count + 1
        )
        for oldIndex in oldTokens.indices.reversed() {
            for newIndex in newTokens.indices.reversed() {
                if oldTokens[oldIndex].value == newTokens[newIndex].value {
                    lengths[oldIndex][newIndex] = lengths[oldIndex + 1][newIndex + 1] + 1
                } else {
                    lengths[oldIndex][newIndex] = max(
                        lengths[oldIndex + 1][newIndex],
                        lengths[oldIndex][newIndex + 1]
                    )
                }
            }
        }

        var matchedOld = Array(repeating: false, count: oldTokens.count)
        var matchedNew = Array(repeating: false, count: newTokens.count)
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldTokens.count, newIndex < newTokens.count {
            if oldTokens[oldIndex].value == newTokens[newIndex].value {
                matchedOld[oldIndex] = true
                matchedNew[newIndex] = true
                oldIndex += 1
                newIndex += 1
            } else if lengths[oldIndex + 1][newIndex] >= lengths[oldIndex][newIndex + 1] {
                oldIndex += 1
            } else {
                newIndex += 1
            }
        }

        return IntralineDiffHighlights(
            old: unmatchedRanges(in: oldTokens, matched: matchedOld),
            new: unmatchedRanges(in: newTokens, matched: matchedNew)
        )
    }

    private static func tokens(in source: String) -> [Token] {
        let characters = Array(source)
        var result: [Token] = []
        var start = 0

        while start < characters.count {
            let kind = tokenKind(for: characters[start])
            var end = start + 1
            while end < characters.count, tokenKind(for: characters[end]) == kind {
                end += 1
            }
            result.append(Token(value: String(characters[start..<end]), range: start..<end))
            start = end
        }
        return result
    }

    private static func tokenKind(for character: Character) -> TokenKind {
        if character.isWhitespace { return .whitespace }
        if character.isLetter || character.isNumber || character == "_" || character == "$" {
            return .word
        }
        return .punctuation
    }

    private static func unmatchedRanges(
        in tokens: [Token],
        matched: [Bool]
    ) -> [Range<Int>] {
        let ranges = tokens.indices.compactMap { matched[$0] ? nil : tokens[$0].range }
        guard var current = ranges.first else { return [] }

        var merged: [Range<Int>] = []
        for range in ranges.dropFirst() {
            if current.upperBound == range.lowerBound {
                current = current.lowerBound..<range.upperBound
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    private static func fallbackHighlights(
        from oldSource: String,
        to newSource: String
    ) -> IntralineDiffHighlights {
        let oldCharacters = Array(oldSource)
        let newCharacters = Array(newSource)
        var prefixCount = 0
        while prefixCount < min(oldCharacters.count, newCharacters.count),
              oldCharacters[prefixCount] == newCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < min(oldCharacters.count, newCharacters.count) - prefixCount,
              oldCharacters[oldCharacters.count - suffixCount - 1]
                == newCharacters[newCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        let oldEnd = oldCharacters.count - suffixCount
        let newEnd = newCharacters.count - suffixCount
        return IntralineDiffHighlights(
            old: prefixCount < oldEnd ? [prefixCount..<oldEnd] : [],
            new: prefixCount < newEnd ? [prefixCount..<newEnd] : []
        )
    }
}
