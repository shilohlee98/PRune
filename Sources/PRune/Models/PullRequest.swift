import Foundation

struct GitHubAccount: Identifiable, Hashable, Sendable {
    let host: String
    let login: String
    let state: String
    let isActive: Bool

    var id: String { "\(host)|\(login)" }
    var isAuthenticated: Bool { state == "success" }
}

enum PullRequestScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case reviewing = "Reviewing"
    case authored = "Authored"

    var id: String { rawValue }
}

enum PullRequestStatus: String, Sendable {
    case open = "Open"
    case draft = "Draft"
    case closed = "Closed"
    case merged = "Merged"
}

enum PullRequestStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case open = "Open"
    case draft = "Draft"
    case closed = "Closed"
    case merged = "Merged"

    var id: String { rawValue }

    func includes(_ status: PullRequestStatus) -> Bool {
        switch self {
        case .all:
            true
        case .open:
            status == .open
        case .draft:
            status == .draft
        case .closed:
            status == .closed
        case .merged:
            status == .merged
        }
    }
}

enum CheckState: String, CaseIterable, Identifiable, Sendable {
    case all = "Any status"
    case success = "Successful"
    case pending = "In progress"
    case failed = "Action required"

    var id: String { rawValue }
}

struct PullRequestCheck: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let state: CheckState
}

struct PullRequestCommit: Identifiable, Hashable, Sendable {
    var id: String { oid }
    let oid: String
    let messageHeadline: String
    let authoredDate: Date
    let authorLogin: String

    var shortOID: String {
        String(oid.prefix(7))
    }

    var ageLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(authoredDate)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        if seconds < 604_800 { return "\(seconds / 86_400)d" }
        return "\(seconds / 604_800)w"
    }
}

enum PullRequestCommentKind: String, Hashable, Sendable {
    case conversation
    case review
}

struct PullRequestComment: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue)-\(databaseID)" }
    let databaseID: Int
    let kind: PullRequestCommentKind
    let authorLogin: String
    let authorAvatarURL: URL?
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let webURL: URL?
    let path: String?
    let line: Int?
    let diffSide: String?
    let diffHunk: String?
    let isOutdated: Bool
    let reviewThreadID: String?
    let isResolved: Bool
    let viewerCanReply: Bool
    let viewerCanResolve: Bool
    let viewerCanUnresolve: Bool
    let inReplyToID: Int?

    var ageLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(createdAt)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        if seconds < 604_800 { return "\(seconds / 86_400)d" }
        return "\(seconds / 604_800)w"
    }

    var isEdited: Bool {
        updatedAt.timeIntervalSince(createdAt) > 1
    }

    var replyRootID: Int {
        inReplyToID ?? databaseID
    }
}

enum DiffLineKind: Sendable {
    case context
    case addition
    case deletion
}

struct PullRequestDiffLine: Identifiable, Hashable, Sendable {
    let id: String
    let kind: DiffLineKind
    let oldLine: Int?
    let newLine: Int?
    let content: String

    var reviewLine: Int? { newLine ?? oldLine }
    var reviewSide: String { newLine == nil ? "LEFT" : "RIGHT" }
}

struct PullRequestDiffHunk: Identifiable, Hashable, Sendable {
    let id: String
    let header: String
    let lines: [PullRequestDiffLine]
    let splitRows: [PullRequestSplitDiffRow]

    init(id: String, header: String, lines: [PullRequestDiffLine]) {
        self.id = id
        self.header = header
        self.lines = lines
        splitRows = Self.makeSplitRows(from: lines)
    }

    private static func makeSplitRows(
        from lines: [PullRequestDiffLine]
    ) -> [PullRequestSplitDiffRow] {
        var rows: [PullRequestSplitDiffRow] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if case .context = line.kind {
                rows.append(
                    PullRequestSplitDiffRow(
                        id: "context|\(line.id)",
                        left: line,
                        right: line
                    )
                )
                index += 1
                continue
            }

            var deletions: [PullRequestDiffLine] = []
            var additions: [PullRequestDiffLine] = []
            while index < lines.count {
                let changedLine = lines[index]
                if case .context = changedLine.kind { break }
                switch changedLine.kind {
                case .deletion: deletions.append(changedLine)
                case .addition: additions.append(changedLine)
                case .context: break
                }
                index += 1
            }

            for offset in 0..<max(deletions.count, additions.count) {
                let left = offset < deletions.count ? deletions[offset] : nil
                let right = offset < additions.count ? additions[offset] : nil
                rows.append(
                    PullRequestSplitDiffRow(
                        id: "change|\(left?.id ?? "blank")|\(right?.id ?? "blank")|\(offset)",
                        left: left,
                        right: right
                    )
                )
            }
        }

        return rows
    }
}

struct PullRequestSplitDiffRow: Identifiable, Hashable, Sendable {
    let id: String
    let left: PullRequestDiffLine?
    let right: PullRequestDiffLine?
}

struct PullRequestDiffFile: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let hunks: [PullRequestDiffHunk]
    let additions: Int
    let deletions: Int
}

struct CodeNavigationTarget: Identifiable, Hashable, Sendable {
    let id = UUID()
    let path: String
    let line: Int?
    let side: String?

    static func fileAnchor(for path: String) -> String {
        "code-file|\(path)"
    }

    static func lineAnchor(path: String, line: Int, side: String) -> String {
        "code-line|\(path)|\(side.uppercased())|\(line)"
    }

    func anchor(in files: [PullRequestDiffFile]) -> String {
        guard let file = files.first(where: { $0.path == path }) else {
            return Self.fileAnchor(for: path)
        }
        guard let line else { return Self.fileAnchor(for: path) }
        let normalizedSide = side?.uppercased()
        let matchingLine = file.hunks
            .flatMap(\.lines)
            .first { diffLine in
                switch normalizedSide {
                case "LEFT": diffLine.oldLine == line
                case "RIGHT": diffLine.newLine == line
                default: diffLine.reviewLine == line
                }
            }
        guard matchingLine != nil else {
            return Self.fileAnchor(for: path)
        }
        return Self.lineAnchor(
            path: path,
            line: line,
            side: normalizedSide ?? matchingLine?.reviewSide ?? "RIGHT"
        )
    }

    func matches(path: String, line: PullRequestDiffLine) -> Bool {
        matches(path: path, lineNumber: line.reviewLine, side: line.reviewSide)
    }

    func matches(path: String, lineNumber: Int?, side: String) -> Bool {
        guard self.path == path, let targetLine = self.line else { return false }
        return lineNumber == targetLine
            && (self.side.map { side == $0.uppercased() } ?? true)
    }
}

struct DraftReviewComment: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: String
    let line: Int
    let side: String
    let body: String
    let commitOID: String?

    init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        side: String,
        body: String,
        commitOID: String? = nil
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.body = body
        self.commitOID = commitOID
    }
}

enum ReviewEvent: String, CaseIterable, Identifiable, Sendable {
    case comment = "Comment"
    case approve = "Approve"
    case requestChanges = "Request changes"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .comment: "COMMENT"
        case .approve: "APPROVE"
        case .requestChanges: "REQUEST_CHANGES"
        }
    }
}

enum PullRequestMergeMethod: String, CaseIterable, Identifiable, Sendable {
    case merge = "Merge"
    case squash = "Squash and merge"
    case rebase = "Rebase and merge"

    var id: String { rawValue }

    var commandFlag: String {
        switch self {
        case .merge: "--merge"
        case .squash: "--squash"
        case .rebase: "--rebase"
        }
    }
}

struct PullRequest: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let repositoryFullName: String
    let author: String
    let updatedAt: Date
    let webURL: URL
    var isDraft: Bool
    var scopes: Set<PullRequestScope>
    var status: PullRequestStatus = .open

    var branch = ""
    var baseBranch = ""
    var body = ""
    var additions = 0
    var deletions = 0
    var comments = 0
    var reviewers: [String] = []
    var checks: [PullRequestCheck] = []
    var commits: [PullRequestCommit] = []
    var headRefOID = ""
    var mergeable = "UNKNOWN"
    var mergeStateStatus = "UNKNOWN"
    var reviewDecision = ""
    var allowedMergeMethods = Set(PullRequestMergeMethod.allCases)
    var autoMergeAllowed = false
    var autoMergeEnabled = false
    var detailsLoaded = false

    var repositoryName: String {
        repositoryFullName.split(separator: "/").last.map(String.init) ?? repositoryFullName
    }

    var ageLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        if seconds < 604_800 { return "\(seconds / 86_400)d" }
        return "\(seconds / 604_800)w"
    }

    var checkState: CheckState {
        if checks.contains(where: { $0.state == .failed }) { return .failed }
        if checks.isEmpty || checks.contains(where: { $0.state == .pending }) { return .pending }
        return .success
    }

    var mergeBlockReason: String? {
        if status == .merged {
            return "Pull request has already been merged"
        }
        if status == .closed {
            return "Pull request is closed"
        }
        guard detailsLoaded, !headRefOID.isEmpty else {
            return "Loading merge status"
        }
        if isDraft {
            return "Mark the pull request ready before merging"
        }
        if mergeable == "CONFLICTING" || mergeStateStatus == "DIRTY" {
            return "Resolve merge conflicts before merging"
        }
        switch reviewDecision {
        case "REVIEW_REQUIRED":
            return "Required review has not been approved"
        case "CHANGES_REQUESTED":
            return "Changes were requested in review"
        default:
            break
        }
        switch mergeStateStatus {
        case "BLOCKED":
            return "Branch protection requirements are not satisfied"
        case "BEHIND":
            return "Update the branch before merging"
        case "DRAFT":
            return "Mark the pull request ready before merging"
        case "UNKNOWN":
            return "GitHub is still calculating mergeability"
        default:
            return nil
        }
    }

    var statusLabel: String {
        switch status {
        case .open:
            isDraft ? "Draft" : "Ready for review"
        case .draft:
            "Draft"
        case .closed:
            "Closed"
        case .merged:
            "Merged"
        }
    }
}

extension PullRequest {
    static let samples: [PullRequest] = {
        let now = Date()

        func sample(
            _ number: Int,
            repo: String,
            title: String,
            branch: String,
            days: Double,
            additions: Int,
            deletions: Int,
            state: CheckState,
            scopes: Set<PullRequestScope> = [.authored]
        ) -> PullRequest {
            var pullRequest = PullRequest(
                id: "sample-\(repo)-\(number)",
                number: number,
                title: title,
                repositoryFullName: "plaxieappier/\(repo)",
                author: scopes.contains(.authored) ? "shiloh-lee-appier" : "teammate-appier",
                updatedAt: now.addingTimeInterval(-days * 86_400),
                webURL: URL(string: "https://github.com/plaxieappier/\(repo)/pull/\(number)")!,
                isDraft: state == .failed,
                scopes: scopes
            )
            pullRequest.status = pullRequest.isDraft ? .draft : .open
            pullRequest.branch = branch
            pullRequest.baseBranch = "develop"
            pullRequest.body = "## Motivation and Context\nPHXX-\(number)\n\n## Description\nThis pull request keeps the change focused and adds regression coverage for the updated behavior.\n\n## Checklist\n- [x] I have performed a self-review of my code\n- [x] I have described the pull request clearly\n- [ ] I have made the pull request small"
            pullRequest.additions = additions
            pullRequest.deletions = deletions
            pullRequest.comments = number % 7
            pullRequest.reviewers = ["YL", "JC", "AL", "MH"]
            pullRequest.checks = [
                PullRequestCheck(id: "info-\(number)", name: "check-bb-pr-info", state: .success),
                PullRequestCheck(id: "notify-\(number)", name: "call-shared / notify", state: .success),
                PullRequestCheck(id: "ci-\(number)", name: "continuous-integration/jenkins/pr-merge", state: state),
            ]
            let previewOID = "preview-\(repo)-\(number)"
            pullRequest.commits = [
                PullRequestCommit(
                    oid: previewOID,
                    messageHeadline: title,
                    authoredDate: pullRequest.updatedAt,
                    authorLogin: pullRequest.author
                ),
            ]
            pullRequest.headRefOID = previewOID
            pullRequest.detailsLoaded = true
            return pullRequest
        }

        return [
            sample(6793, repo: "backend", title: "fix: repair legacy LINE mappings from bulk uploads", branch: "shiloh/PHXX-6793-line-bulk-upsert", days: 0.01, additions: 595, deletions: 18, state: .success),
            sample(6799, repo: "backend", title: "fix: normalize HTTP route labels to reduce time-series cardinality", branch: "shiloh/PHXX-6799-reduce-influx-metric-cardinality", days: 3, additions: 444, deletions: 67, state: .pending),
            sample(6795, repo: "backend", title: "perf: add journey map list summary API", branch: "shiloh/PHXX-6795-add-jm-list-summary-api", days: 3.1, additions: 283, deletions: 20, state: .success),
            sample(6787, repo: "backend", title: "chore: add consumer group tag to Kafka processing counts", branch: "shiloh/PHXX-6787-kafka-metrics-consumer-group", days: 4, additions: 58, deletions: 1, state: .failed),
            sample(3548, repo: "frontend", title: "perf: fetch journey map summaries for list", branch: "shiloh/PHXX-6795-fetch-jm-list-summary", days: 3.2, additions: 92, deletions: 37, state: .success),
            sample(3547, repo: "frontend", title: "fix: debounce automation list search", branch: "shiloh/PHXX-6791-automation-search-debounce", days: 4.2, additions: 26, deletions: 4, state: .pending, scopes: [.reviewing]),
            sample(912, repo: "realtime-segment-system", title: "fix: handle CUS match conflicts during profile merge", branch: "shiloh/PHXX-6694-fix-cus-profile-merge", days: 5, additions: 108, deletions: 7, state: .success),
            sample(905, repo: "realtime-segment-system", title: "chore: expose consumer rebalance duration histogram", branch: "daniel/segment-rebalance-metrics", days: 7, additions: 76, deletions: 9, state: .failed, scopes: [.reviewing]),
        ]
    }()
}
