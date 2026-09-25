import Foundation

enum FuzzySearch {
    static func score(_ query: String, in values: [String]) -> Int? {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return 0 }

        var total = 0
        for term in terms {
            guard let best = values.compactMap({ score(String(term), in: $0) }).max() else {
                return nil
            }
            total += best
        }
        return total
    }

    private static func score(_ term: String, in value: String) -> Int? {
        let needle = Array(term.lowercased())
        let haystack = Array(value.lowercased())
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }

        // Keep the best alignment at each character so a later consecutive match
        // can outrank an earlier match with large gaps.
        var previous = Array(repeating: Int.min, count: haystack.count)
        for (termIndex, character) in needle.enumerated() {
            var current = Array(repeating: Int.min, count: haystack.count)
            var bestGap = Int.min

            for index in haystack.indices {
                if index > 0, previous[index - 1] != Int.min {
                    bestGap = max(bestGap, previous[index - 1] + index - 1)
                }
                guard haystack[index] == character else { continue }

                let boundaryBonus = index == 0
                    || !haystack[index - 1].isLetter && !haystack[index - 1].isNumber
                    ? 12 : 0

                if termIndex == 0 {
                    current[index] = 10 + boundaryBonus - min(index, 20)
                } else {
                    if bestGap != Int.min {
                        current[index] = bestGap + 10 + boundaryBonus - index + 1
                    }
                    if index > 0, previous[index - 1] != Int.min {
                        current[index] = max(
                            current[index],
                            previous[index - 1] + 10 + boundaryBonus + 15
                        )
                    }
                }
            }
            previous = current
        }

        guard let best = previous.max(), best != Int.min else { return nil }
        let exactBonus = value.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            == nil ? 0 : 30
        return best + exactBonus - min(haystack.count / 4, 20)
    }
}
