import Foundation
import SwiftUI

enum FindHighlight {
    static func apply(_ query: String, to value: AttributedString) -> AttributedString {
        guard !query.isEmpty else { return value }
        var result = value
        let source = String(result.characters)
        var searchStart = source.startIndex

        while searchStart < source.endIndex,
              let range = source.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<source.endIndex
              ) {
            let lowerOffset = source.distance(from: source.startIndex, to: range.lowerBound)
            let upperOffset = source.distance(from: source.startIndex, to: range.upperBound)
            let lowerBound = result.characters.index(result.startIndex, offsetBy: lowerOffset)
            let upperBound = result.characters.index(result.startIndex, offsetBy: upperOffset)
            result[lowerBound..<upperBound].backgroundColor = Color.yellow.opacity(0.45)
            searchStart = range.upperBound
        }
        return result
    }

    static func contains(_ query: String, in value: String) -> Bool {
        !query.isEmpty && value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}
