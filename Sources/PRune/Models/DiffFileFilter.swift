import Foundation

struct DiffFileFilter: Equatable {
    enum PathMode: String, CaseIterable {
        case include
        case exclude

        var title: String { rawValue.capitalized }
    }

    struct PathOption: Equatable, Identifiable {
        let query: String
        var isSelected = true
        var mode: PathMode = .include

        var id: String { query }
    }

    var pathQuery = ""
    var pathQueryMode: PathMode = .include
    var pathOptions: [PathOption] = []
    var hiddenExtensions: Set<String> = []
    var includesViewed = true
    var includesUnviewed = true

    var isActive: Bool {
        !pathQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pathOptions.contains(where: \.isSelected) || !hiddenExtensions.isEmpty
            || !includesViewed || !includesUnviewed
    }

    mutating func addPathQuery() {
        let query = pathQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if let index = pathOptions.firstIndex(where: {
            $0.query.caseInsensitiveCompare(query) == .orderedSame
        }) {
            pathOptions[index].isSelected = true
            pathOptions[index].mode = pathQueryMode
        } else {
            pathOptions.append(PathOption(query: query, mode: pathQueryMode))
        }
        pathQuery = ""
    }

    func matches(path: String, isViewed: Bool) -> Bool {
        guard !hiddenExtensions.contains(Self.extensionKey(for: path)),
              isViewed ? includesViewed : includesUnviewed else { return false }

        let query = pathQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedOptions = pathOptions.filter(\.isSelected)
        if selectedOptions.contains(where: {
            $0.mode == .exclude && Self.matchesPath(path, query: $0.query)
        }) || (!query.isEmpty && pathQueryMode == .exclude && Self.matchesPath(path, query: query)) {
            return false
        }

        let includeOptions = selectedOptions.filter { $0.mode == .include }
        let hasIncludeQuery = !query.isEmpty && pathQueryMode == .include
        return (!hasIncludeQuery && includeOptions.isEmpty)
            || (hasIncludeQuery && Self.matchesPath(path, query: query))
            || includeOptions.contains { Self.matchesPath(path, query: $0.query) }
    }

    static func matchesPath(_ path: String, query: String) -> Bool {
        guard query.contains("*") || query.contains("?") else {
            return path.localizedCaseInsensitiveContains(query)
        }

        let pattern = "^" + query.map { character in
            switch character {
            case "*": ".*"
            case "?": "."
            default: NSRegularExpression.escapedPattern(for: String(character))
            }
        }.joined() + "$"
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        return path.range(of: pattern, options: options) != nil
            || (path as NSString).lastPathComponent.range(of: pattern, options: options) != nil
    }

    static func extensionKey(for path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }
}
