import Foundation

struct PullRequestPage: Sendable {
    let items: [PullRequest]
    let hasMore: Bool
}

struct GitHubService: Sendable {
    func fetchAuthenticatedAccounts() async throws -> [GitHubAccount] {
        let data = try await run(["auth", "status", "--json", "hosts"])
        let response = try JSONDecoder().decode(GHAuthStatusEnvelope.self, from: data)

        return response.hosts
            .flatMap { host, accounts in
                accounts.map { account in
                    GitHubAccount(
                        host: account.host.isEmpty ? host : account.host,
                        login: account.login,
                        state: account.state,
                        isActive: account.active
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                if lhs.host != rhs.host {
                    return lhs.host.localizedStandardCompare(rhs.host) == .orderedAscending
                }
                return lhs.login.localizedStandardCompare(rhs.login) == .orderedAscending
            }
    }

    func switchAccount(to account: GitHubAccount) async throws {
        _ = try await run([
            "auth", "switch",
            "--hostname", account.host,
            "--user", account.login,
        ])
    }

    func fetchViewerLogin() async throws -> String {
        let data = try await run(["api", "user", "--jq", ".login"])
        guard let login = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !login.isEmpty
        else {
            throw GitHubServiceError.invalidResponse("GitHub did not return the current user.")
        }
        return login
    }

    func fetchPullRequests(
        scope: PullRequestScope,
        status: PullRequestStatusFilter,
        limit: Int
    ) async throws -> PullRequestPage {
        if scope != .all {
            let flag = scope == .authored ? "--author" : "--review-requested"
            let page = try await search(flag: flag, status: status, limit: limit)
            return PullRequestPage(
                items: try await fetchStatistics(for: page.items),
                hasMore: page.hasMore
            )
        }

        async let authored = search(flag: "--author", status: status, limit: limit)
        async let reviewing = search(flag: "--review-requested", status: status, limit: limit)
        let (authoredPage, reviewingPage) = try await (authored, reviewing)

        var merged: [String: PullRequest] = [:]
        for item in authoredPage.items {
            merged[item.id] = item
        }
        for var item in reviewingPage.items {
            if var existing = merged[item.id] {
                existing.scopes.insert(.reviewing)
                merged[item.id] = existing
            } else {
                item.scopes = [.reviewing]
                merged[item.id] = item
            }
        }

        let pullRequests = Array(
            merged.values
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(limit)
        )
        return PullRequestPage(
            items: try await fetchStatistics(for: pullRequests),
            hasMore: merged.count > limit || authoredPage.hasMore || reviewingPage.hasMore
        )
    }

    func fetchDetails(for pullRequest: PullRequest) async throws -> PullRequest {
        async let detailRequest = run([
            "pr", "view", String(pullRequest.number),
            "--repo", pullRequest.repositoryFullName,
            "--json", "additions,deletions,baseRefName,body,commits,headRefName,headRefOid,reviewRequests,reviews,statusCheckRollup,mergeable,mergeStateStatus,reviewDecision,autoMergeRequest",
        ])
        async let mergeSettingsRequest = try? run([
            "api", "repos/\(pullRequest.repositoryFullName)",
        ])

        let data = try await detailRequest
        let mergeSettingsData = await mergeSettingsRequest
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let detail = try decoder.decode(GHDetail.self, from: data)
        let mergeSettings = mergeSettingsData.flatMap {
            try? decoder.decode(GHRepositoryMergeSettings.self, from: $0)
        }
        var updated = pullRequest
        updated.branch = detail.headRefName
        updated.baseBranch = detail.baseRefName
        updated.body = detail.body
        updated.additions = detail.additions
        updated.deletions = detail.deletions
        updated.reviewers = Array(
            Set(
                detail.reviewRequests.compactMap(\.login)
                    + detail.reviews.compactMap { $0.author?.login }
            )
        ).sorted()
        updated.checks = detail.statusCheckRollup.enumerated().map { index, check in
            PullRequestCheck(
                id: "\(pullRequest.id)-check-\(index)",
                name: check.displayName,
                state: check.checkState
            )
        }
        updated.commits = detail.commits.map { commit in
            PullRequestCommit(
                oid: commit.oid,
                messageHeadline: commit.messageHeadline,
                authoredDate: commit.authoredDate,
                authorLogin: commit.authors.first?.login ?? commit.authors.first?.name ?? "unknown"
            )
        }
        updated.headRefOID = detail.headRefOid
        updated.mergeable = detail.mergeable
        updated.mergeStateStatus = detail.mergeStateStatus
        updated.reviewDecision = detail.reviewDecision
        updated.autoMergeEnabled = detail.autoMergeRequest != nil
        if let mergeSettings {
            updated.allowedMergeMethods = Set(
                PullRequestMergeMethod.allCases.filter { method in
                    switch method {
                    case .merge: mergeSettings.allowMergeCommit
                    case .squash: mergeSettings.allowSquashMerge
                    case .rebase: mergeSettings.allowRebaseMerge
                    }
                }
            )
            updated.autoMergeAllowed = mergeSettings.allowAutoMerge
        }
        updated.detailsLoaded = true
        return updated
    }

    func fetchDiff(
        for pullRequest: PullRequest,
        commitOID: String? = nil
    ) async throws -> [PullRequestDiffFile] {
        let data: Data
        if let commitOID {
            data = try await run([
                "api", "repos/\(pullRequest.repositoryFullName)/commits/\(commitOID)",
                "-H", "Accept: application/vnd.github.patch",
            ])
        } else {
            data = try await run([
                "pr", "diff", String(pullRequest.number),
                "--repo", pullRequest.repositoryFullName,
            ])
        }
        guard let patch = String(data: data, encoding: .utf8) else {
            throw GitHubServiceError.invalidResponse("The pull request diff was not valid UTF-8.")
        }
        return Self.parseUnifiedDiff(patch)
    }

    func updateDescription(of pullRequest: PullRequest, body: String) async throws {
        _ = try await run(
            [
                "pr", "edit", String(pullRequest.number),
                "--repo", pullRequest.repositoryFullName,
                "--body-file", "-",
            ],
            stdin: body
        )
    }

    func postComment(on pullRequest: PullRequest, body: String) async throws {
        _ = try await run(
            [
                "pr", "comment", String(pullRequest.number),
                "--repo", pullRequest.repositoryFullName,
                "--body-file", "-",
            ],
            stdin: body
        )
    }

    func fetchActivityComments(for pullRequest: PullRequest) async throws -> [PullRequestComment] {
        async let conversationData = try? run([
            "api", "--paginate", "--slurp",
            "repos/\(pullRequest.repositoryFullName)/issues/\(pullRequest.number)/comments?per_page=100",
        ])
        async let reviewData = try? run([
            "api", "--paginate", "--slurp",
            "repos/\(pullRequest.repositoryFullName)/pulls/\(pullRequest.number)/comments?per_page=100",
        ])
        async let reviewThreadData = try? fetchReviewThreadMetadata(for: pullRequest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let (conversationPayload, reviewPayload, reviewThreadMetadata) = await (
            conversationData,
            reviewData,
            reviewThreadData
        )
        guard conversationPayload != nil || reviewPayload != nil else {
            throw GitHubServiceError.invalidResponse("GitHub did not return pull request comments.")
        }
        let conversationPages = conversationPayload.flatMap {
            try? decoder.decode([[GHIssueComment]].self, from: $0)
        } ?? []
        let reviewPages = reviewPayload.flatMap {
            try? decoder.decode([[GHReviewComment]].self, from: $0)
        } ?? []

        let conversationComments = conversationPages.flatMap { $0 }.map { comment in
            PullRequestComment(
                databaseID: comment.id,
                kind: .conversation,
                authorLogin: comment.user?.login ?? "ghost",
                authorAvatarURL: comment.user?.avatarURL,
                body: comment.body ?? "",
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                webURL: comment.htmlURL,
                path: nil,
                line: nil,
                diffSide: nil,
                diffHunk: nil,
                isOutdated: false,
                reviewThreadID: nil,
                isResolved: false,
                viewerCanReply: false,
                viewerCanResolve: false,
                viewerCanUnresolve: false,
                inReplyToID: nil
            )
        }
        let reviewComments = reviewPages.flatMap { $0 }.map { comment in
            let thread = reviewThreadMetadata?[comment.id]
            return PullRequestComment(
                databaseID: comment.id,
                kind: .review,
                authorLogin: comment.user?.login ?? "ghost",
                authorAvatarURL: comment.user?.avatarURL,
                body: comment.body ?? "",
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                webURL: comment.htmlURL,
                path: comment.path,
                line: comment.line ?? comment.originalLine,
                diffSide: comment.side ?? comment.originalSide,
                diffHunk: comment.diffHunk,
                isOutdated: comment.line == nil && comment.originalLine != nil,
                reviewThreadID: thread?.id,
                isResolved: thread?.isResolved ?? false,
                viewerCanReply: thread?.viewerCanReply ?? true,
                viewerCanResolve: thread?.viewerCanResolve ?? false,
                viewerCanUnresolve: thread?.viewerCanUnresolve ?? false,
                inReplyToID: comment.inReplyToID
            )
        }

        return (conversationComments + reviewComments).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.databaseID < rhs.databaseID
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func updateReviewThread(
        _ comment: PullRequestComment,
        resolved: Bool
    ) async throws {
        guard let threadID = comment.reviewThreadID else {
            throw GitHubServiceError.invalidResponse("The GitHub review thread ID is unavailable.")
        }

        let mutation = resolved ? "resolveReviewThread" : "unresolveReviewThread"
        let query = """
        mutation UpdateReviewThread($threadId: ID!) {
          updateThread: \(mutation)(input: {threadId: $threadId}) {
            thread {
              id
              isResolved
            }
          }
        }
        """
        let data = try await runJSON(
            ["api", "graphql", "--input", "-"],
            payload: GHReviewThreadMutationRequest(
                query: query,
                variables: GHReviewThreadMutationVariables(threadID: threadID)
            )
        )
        let response = try JSONDecoder().decode(GHReviewThreadMutationEnvelope.self, from: data)
        if let message = response.errors?.first?.message {
            throw GitHubServiceError.invalidResponse(message)
        }
        guard let thread = response.data?.updateThread?.thread else {
            throw GitHubServiceError.invalidResponse("GitHub did not return the updated review thread.")
        }
        guard thread.id == threadID, thread.isResolved == resolved else {
            throw GitHubServiceError.invalidResponse("GitHub returned an unexpected review thread state.")
        }
    }

    func updateComment(
        _ comment: PullRequestComment,
        on pullRequest: PullRequest,
        body: String
    ) async throws {
        let endpoint = comment.kind == .conversation
            ? "repos/\(pullRequest.repositoryFullName)/issues/comments/\(comment.databaseID)"
            : "repos/\(pullRequest.repositoryFullName)/pulls/comments/\(comment.databaseID)"
        _ = try await runJSON(
            ["api", "--method", "PATCH", endpoint, "--input", "-"],
            payload: GHCommentBodyPayload(body: body)
        )
    }

    func deleteComment(
        _ comment: PullRequestComment,
        on pullRequest: PullRequest
    ) async throws {
        let endpoint = comment.kind == .conversation
            ? "repos/\(pullRequest.repositoryFullName)/issues/comments/\(comment.databaseID)"
            : "repos/\(pullRequest.repositoryFullName)/pulls/comments/\(comment.databaseID)"
        _ = try await run(["api", "--method", "DELETE", endpoint])
    }

    func reply(
        to comment: PullRequestComment,
        on pullRequest: PullRequest,
        body: String
    ) async throws {
        switch comment.kind {
        case .conversation:
            try await postComment(on: pullRequest, body: body)
        case .review:
            _ = try await runJSON(
                [
                    "api", "--method", "POST",
                    "repos/\(pullRequest.repositoryFullName)/pulls/\(pullRequest.number)/comments/\(comment.replyRootID)/replies",
                    "--input", "-",
                ],
                payload: GHCommentBodyPayload(body: body)
            )
        }
    }

    private func fetchReviewThreadMetadata(
        for pullRequest: PullRequest
    ) async throws -> [Int: GHReviewThreadMetadata] {
        let repository = pullRequest.repositoryFullName.split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: true
        )
        guard repository.count == 2 else {
            throw GitHubServiceError.invalidResponse("The GitHub repository name is invalid.")
        }

        let query = """
        query ReviewThreads($owner: String!, $name: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100, after: $cursor) {
                nodes {
                  id
                  isResolved
                  viewerCanReply
                  viewerCanResolve
                  viewerCanUnresolve
                  comments(first: 100) {
                    nodes {
                      databaseId
                    }
                  }
                }
                pageInfo {
                  hasNextPage
                  endCursor
                }
              }
            }
          }
        }
        """

        var result: [Int: GHReviewThreadMetadata] = [:]
        var cursor: String?

        repeat {
            let data = try await runJSON(
                ["api", "graphql", "--input", "-"],
                payload: GHReviewThreadsRequest(
                    query: query,
                    variables: GHReviewThreadsVariables(
                        owner: String(repository[0]),
                        name: String(repository[1]),
                        number: pullRequest.number,
                        cursor: cursor
                    )
                )
            )
            let response = try JSONDecoder().decode(GHReviewThreadsEnvelope.self, from: data)
            if let message = response.errors?.first?.message {
                throw GitHubServiceError.invalidResponse(message)
            }
            guard let connection = response.data?.repository?.pullRequest?.reviewThreads else {
                throw GitHubServiceError.invalidResponse("GitHub did not return review threads.")
            }

            for thread in connection.nodes {
                let metadata = GHReviewThreadMetadata(
                    id: thread.id,
                    isResolved: thread.isResolved,
                    viewerCanReply: thread.viewerCanReply,
                    viewerCanResolve: thread.viewerCanResolve,
                    viewerCanUnresolve: thread.viewerCanUnresolve
                )
                for comment in thread.comments.nodes {
                    if let databaseID = comment.databaseID {
                        result[databaseID] = metadata
                    }
                }
            }

            cursor = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while cursor != nil

        return result
    }

    func updateDraftState(of pullRequest: PullRequest, isDraft: Bool) async throws {
        var arguments = [
            "pr", "ready", String(pullRequest.number),
            "--repo", pullRequest.repositoryFullName,
        ]
        if isDraft {
            arguments.append("--undo")
        }
        _ = try await run(arguments)
    }

    func updateClosedState(of pullRequest: PullRequest, isClosed: Bool) async throws {
        _ = try await run([
            "pr", isClosed ? "close" : "reopen", String(pullRequest.number),
            "--repo", pullRequest.repositoryFullName,
        ])
    }

    func submitReview(
        on pullRequest: PullRequest,
        event: ReviewEvent,
        body: String,
        comments: [DraftReviewComment],
        commitID: String? = nil
    ) async throws {
        let reviewCommitID = commitID ?? pullRequest.headRefOID
        guard !reviewCommitID.isEmpty else {
            throw GitHubServiceError.invalidResponse("The pull request head commit is unavailable.")
        }

        let payload = ReviewPayload(
            commitID: reviewCommitID,
            body: body,
            event: event.apiValue,
            comments: comments.map {
                ReviewCommentPayload(path: $0.path, line: $0.line, side: $0.side, body: $0.body)
            }
        )
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw GitHubServiceError.invalidResponse("Could not encode the review payload.")
        }

        _ = try await run(
            [
                "api", "--method", "POST",
                "repos/\(pullRequest.repositoryFullName)/pulls/\(pullRequest.number)/reviews",
                "--input", "-",
            ],
            stdin: payloadString
        )
    }

    func mergePullRequest(
        _ pullRequest: PullRequest,
        method: PullRequestMergeMethod,
        automatically: Bool
    ) async throws {
        var arguments = [
            "pr", "merge", String(pullRequest.number),
            "--repo", pullRequest.repositoryFullName,
            method.commandFlag,
            "--match-head-commit", pullRequest.headRefOID,
        ]
        if automatically {
            arguments.append("--auto")
        }
        _ = try await run(arguments)
    }

    func disableAutoMerge(for pullRequest: PullRequest) async throws {
        _ = try await run([
            "pr", "merge", String(pullRequest.number),
            "--repo", pullRequest.repositoryFullName,
            "--disable-auto",
        ])
    }

    private func search(
        flag: String,
        status: PullRequestStatusFilter,
        limit: Int
    ) async throws -> PullRequestSearchPage {
        let requestLimit = limit + 1
        let data = try await run(
            searchArguments(flag: flag, status: status, limit: requestLimit)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([GHSearchItem].self, from: data)
        let mergedURLs: Set<String>
        if status == .all {
            let mergedData = try await run(
                searchArguments(flag: flag, status: .merged, limit: requestLimit)
            )
            mergedURLs = Set(
                try decoder.decode([GHSearchItem].self, from: mergedData).map(\.url)
            )
        } else {
            mergedURLs = []
        }
        let scope: PullRequestScope = flag == "--author" ? .authored : .reviewing
        let pullRequests = items.prefix(limit).map { item in
            var pullRequest = PullRequest(
                id: item.url,
                number: item.number,
                title: item.title,
                repositoryFullName: item.repository.nameWithOwner,
                author: item.author?.login ?? "unknown",
                updatedAt: item.updatedAt,
                webURL: URL(string: item.url)!,
                isDraft: item.isDraft,
                scopes: [scope]
            )
            pullRequest.status = switch status {
            case .all:
                if mergedURLs.contains(item.url) {
                    .merged
                } else if item.isDraft {
                    .draft
                } else if item.state.uppercased() == "CLOSED" {
                    .closed
                } else {
                    .open
                }
            case .open:
                .open
            case .draft:
                .draft
            case .closed:
                .closed
            case .merged:
                .merged
            }
            pullRequest.comments = item.commentsCount
            return pullRequest
        }
        return PullRequestSearchPage(
            items: Array(pullRequests),
            hasMore: items.count > limit
        )
    }

    private func searchArguments(
        flag: String,
        status: PullRequestStatusFilter,
        limit: Int
    ) -> [String] {
        var arguments = ["search", "prs", flag, "@me"]
        var query: String?

        switch status {
        case .all:
            break
        case .open:
            arguments += ["--state", "open"]
            query = "-is:draft"
        case .draft:
            arguments += ["--state", "open", "--draft"]
        case .closed:
            arguments += ["--state", "closed"]
            query = "-is:merged"
        case .merged:
            arguments.append("--merged")
        }

        arguments += [
            "--limit", String(limit),
            "--sort", "updated",
            "--json", "number,title,repository,updatedAt,url,isDraft,state,author,commentsCount",
        ]
        if let query {
            arguments += ["--", query]
        }
        return arguments
    }

    private func fetchStatistics(for pullRequests: [PullRequest]) async throws -> [PullRequest] {
        guard !pullRequests.isEmpty else { return [] }

        var enriched = pullRequests
        let batchSize = 50

        for batchStart in stride(from: 0, to: enriched.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, enriched.count)
            let indices = Array(batchStart..<batchEnd)
            let fields = indices.enumerated().compactMap { offset, index -> String? in
                let repository = enriched[index].repositoryFullName.split(
                    separator: "/",
                    maxSplits: 1,
                    omittingEmptySubsequences: true
                )
                guard repository.count == 2 else { return nil }
                return """
                pr\(offset): repository(owner: "\(repository[0])", name: "\(repository[1])") {
                  pullRequest(number: \(enriched[index].number)) {
                    url
                    additions
                    deletions
                  }
                }
                """
            }
            let query = "query {\n\(fields.joined(separator: "\n"))\n}"
            let requestData = try JSONEncoder().encode(GHGraphQLRequest(query: query))
            guard let request = String(data: requestData, encoding: .utf8) else {
                throw GitHubServiceError.invalidResponse("Could not encode the pull request statistics query.")
            }

            let responseData = try await run(["api", "graphql", "--input", "-"], stdin: request)
            let response = try JSONDecoder().decode(GHStatisticsEnvelope.self, from: responseData)

            for (offset, index) in indices.enumerated() {
                guard let statistics = response.data["pr\(offset)"]?.pullRequest else { continue }
                enriched[index].additions = statistics.additions
                enriched[index].deletions = statistics.deletions
            }
        }

        return enriched
    }

    private func run(_ arguments: [String], stdin: String? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = try Self.githubExecutable()
                    process.arguments = arguments

                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr
                    let input = stdin.map { _ in Pipe() }
                    process.standardInput = input

                    try process.run()
                    if let stdin, let input {
                        input.fileHandleForWriting.write(Data(stdin.utf8))
                        try? input.fileHandleForWriting.close()
                    }
                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        throw GitHubServiceError.commandFailed(message ?? "gh command failed")
                    }
                    continuation.resume(returning: outputData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runJSON<Payload: Encodable & Sendable>(
        _ arguments: [String],
        payload: Payload
    ) async throws -> Data {
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw GitHubServiceError.invalidResponse("Could not encode the GitHub request.")
        }
        return try await run(arguments, stdin: json)
    }

    static func parseUnifiedDiff(_ patch: String) -> [PullRequestDiffFile] {
        var files: [PullRequestDiffFile] = []
        var path: String?
        var hunks: [PullRequestDiffHunk] = []
        var hunkHeader: String?
        var hunkLines: [PullRequestDiffLine] = []
        var oldLine = 0
        var newLine = 0
        var hunkIndex = 0
        var lineIndex = 0

        func flushHunk() {
            guard let path, let hunkHeader else { return }
            hunks.append(
                PullRequestDiffHunk(
                    id: "\(path)-hunk-\(hunkIndex)",
                    header: hunkHeader,
                    lines: hunkLines
                )
            )
            hunkIndex += 1
            hunkLines = []
        }

        func flushFile() {
            flushHunk()
            hunkHeader = nil
            guard let path else { return }
            var additions = 0
            var deletions = 0
            for line in hunks.flatMap(\.lines) {
                switch line.kind {
                case .addition: additions += 1
                case .deletion: deletions += 1
                case .context: break
                }
            }
            files.append(
                PullRequestDiffFile(
                    path: path,
                    hunks: hunks,
                    additions: additions,
                    deletions: deletions
                )
            )
            hunks = []
            hunkIndex = 0
        }

        for rawLine in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("diff --git ") {
                flushFile()
                hunkHeader = nil
                let parts = line.split(separator: " ")
                if let destination = parts.last, destination.hasPrefix("b/") {
                    path = String(destination.dropFirst(2))
                } else {
                    path = nil
                }
                continue
            }

            if line.hasPrefix("@@ ") {
                flushHunk()
                hunkHeader = line
                hunkLines = []
                lineIndex = 0
                let parts = line.split(separator: " ")
                oldLine = parts.count > 1 ? diffRangeStart(parts[1]) : 0
                newLine = parts.count > 2 ? diffRangeStart(parts[2]) : 0
                continue
            }

            guard hunkHeader != nil, let prefix = line.first else { continue }
            let content = String(line.dropFirst())
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

            hunkLines.append(
                PullRequestDiffLine(
                    id: "\(path ?? "file")-\(hunkIndex)-\(lineIndex)-\(displayedOldLine ?? 0)-\(displayedNewLine ?? 0)",
                    kind: kind,
                    oldLine: displayedOldLine,
                    newLine: displayedNewLine,
                    content: content
                )
            )
            lineIndex += 1
        }
        flushFile()
        return files
    }

    private static func diffRangeStart(_ value: Substring) -> Int {
        let trimmed = value.dropFirst()
        return Int(trimmed.split(separator: ",").first ?? "0") ?? 0
    }

    private static func githubExecutable() throws -> URL {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        throw GitHubServiceError.ghNotInstalled
    }
}

enum GitHubServiceError: LocalizedError {
    case ghNotInstalled
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .ghNotInstalled:
            return "GitHub CLI was not found. Install and authenticate `gh` first."
        case let .commandFailed(message):
            return message
        case let .invalidResponse(message):
            return message
        }
    }
}

private struct GHSearchItem: Decodable, Sendable {
    let number: Int
    let title: String
    let repository: GHRepository
    let updatedAt: Date
    let url: String
    let isDraft: Bool
    let state: String
    let author: GHActor?
    let commentsCount: Int
}

private struct PullRequestSearchPage: Sendable {
    let items: [PullRequest]
    let hasMore: Bool
}

private struct GHAuthStatusEnvelope: Decodable, Sendable {
    let hosts: [String: [GHAuthAccount]]
}

private struct GHAuthAccount: Decodable, Sendable {
    let state: String
    let active: Bool
    let host: String
    let login: String
}

private struct GHGraphQLRequest: Encodable, Sendable {
    let query: String
}

private struct GHGraphQLError: Decodable, Sendable {
    let message: String
}

private struct GHReviewThreadMetadata: Sendable {
    let id: String
    let isResolved: Bool
    let viewerCanReply: Bool
    let viewerCanResolve: Bool
    let viewerCanUnresolve: Bool
}

private struct GHReviewThreadsRequest: Encodable, Sendable {
    let query: String
    let variables: GHReviewThreadsVariables
}

private struct GHReviewThreadsVariables: Encodable, Sendable {
    let owner: String
    let name: String
    let number: Int
    let cursor: String?
}

private struct GHReviewThreadsEnvelope: Decodable, Sendable {
    let data: GHReviewThreadsData?
    let errors: [GHGraphQLError]?
}

private struct GHReviewThreadsData: Decodable, Sendable {
    let repository: GHReviewThreadsRepository?
}

private struct GHReviewThreadsRepository: Decodable, Sendable {
    let pullRequest: GHReviewThreadsPullRequest?
}

private struct GHReviewThreadsPullRequest: Decodable, Sendable {
    let reviewThreads: GHReviewThreadConnection
}

private struct GHReviewThreadConnection: Decodable, Sendable {
    let nodes: [GHReviewThreadNode]
    let pageInfo: GHReviewThreadPageInfo
}

private struct GHReviewThreadPageInfo: Decodable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct GHReviewThreadNode: Decodable, Sendable {
    let id: String
    let isResolved: Bool
    let viewerCanReply: Bool
    let viewerCanResolve: Bool
    let viewerCanUnresolve: Bool
    let comments: GHReviewThreadComments
}

private struct GHReviewThreadComments: Decodable, Sendable {
    let nodes: [GHReviewThreadCommentNode]
}

private struct GHReviewThreadCommentNode: Decodable, Sendable {
    let databaseID: Int?

    enum CodingKeys: String, CodingKey {
        case databaseID = "databaseId"
    }
}

private struct GHReviewThreadMutationRequest: Encodable, Sendable {
    let query: String
    let variables: GHReviewThreadMutationVariables
}

private struct GHReviewThreadMutationVariables: Encodable, Sendable {
    let threadID: String

    enum CodingKeys: String, CodingKey {
        case threadID = "threadId"
    }
}

private struct GHReviewThreadMutationEnvelope: Decodable, Sendable {
    let data: GHReviewThreadMutationData?
    let errors: [GHGraphQLError]?
}

private struct GHReviewThreadMutationData: Decodable, Sendable {
    let updateThread: GHReviewThreadMutationPayload?
}

private struct GHReviewThreadMutationPayload: Decodable, Sendable {
    let thread: GHReviewThreadMutationResult?
}

private struct GHReviewThreadMutationResult: Decodable, Sendable {
    let id: String
    let isResolved: Bool
}

private struct GHStatisticsEnvelope: Decodable, Sendable {
    let data: [String: GHStatisticsRepository]
}

private struct GHStatisticsRepository: Decodable, Sendable {
    let pullRequest: GHStatisticsPullRequest?
}

private struct GHStatisticsPullRequest: Decodable, Sendable {
    let additions: Int
    let deletions: Int
}

private struct GHRepository: Decodable, Sendable {
    let nameWithOwner: String
}

private struct GHActor: Decodable, Sendable {
    let login: String?
}

private struct GHReview: Decodable, Sendable {
    let author: GHActor?
}

private struct GHCommentUser: Decodable, Sendable {
    let login: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

private struct GHIssueComment: Decodable, Sendable {
    let id: Int
    let user: GHCommentUser?
    let body: String?
    let createdAt: Date
    let updatedAt: Date
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
    }
}

private struct GHReviewComment: Decodable, Sendable {
    let id: Int
    let user: GHCommentUser?
    let body: String?
    let createdAt: Date
    let updatedAt: Date
    let htmlURL: URL?
    let path: String?
    let line: Int?
    let originalLine: Int?
    let side: String?
    let originalSide: String?
    let diffHunk: String?
    let inReplyToID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
        case path
        case line
        case originalLine = "original_line"
        case side
        case originalSide = "original_side"
        case diffHunk = "diff_hunk"
        case inReplyToID = "in_reply_to_id"
    }
}

private struct GHCommentBodyPayload: Encodable, Sendable {
    let body: String
}

private struct GHCommit: Decodable, Sendable {
    let authoredDate: Date
    let authors: [GHCommitAuthor]
    let messageHeadline: String
    let oid: String
}

private struct GHCommitAuthor: Decodable, Sendable {
    let login: String?
    let name: String?
}

private struct GHDetail: Decodable, Sendable {
    let additions: Int
    let deletions: Int
    let baseRefName: String
    let body: String
    let commits: [GHCommit]
    let headRefName: String
    let headRefOid: String
    let mergeable: String
    let mergeStateStatus: String
    let reviewDecision: String
    let autoMergeRequest: GHAutoMergeRequest?
    let reviewRequests: [GHActor]
    let reviews: [GHReview]
    let statusCheckRollup: [GHCheck]
}

private struct GHAutoMergeRequest: Decodable, Sendable {}

private struct GHRepositoryMergeSettings: Decodable, Sendable {
    let allowMergeCommit: Bool
    let allowSquashMerge: Bool
    let allowRebaseMerge: Bool
    let allowAutoMerge: Bool

    enum CodingKeys: String, CodingKey {
        case allowMergeCommit = "allow_merge_commit"
        case allowSquashMerge = "allow_squash_merge"
        case allowRebaseMerge = "allow_rebase_merge"
        case allowAutoMerge = "allow_auto_merge"
    }
}

private struct ReviewPayload: Encodable, Sendable {
    let commitID: String
    let body: String
    let event: String
    let comments: [ReviewCommentPayload]

    enum CodingKeys: String, CodingKey {
        case commitID = "commit_id"
        case body
        case event
        case comments
    }
}

private struct ReviewCommentPayload: Encodable, Sendable {
    let path: String
    let line: Int
    let side: String
    let body: String
}

private struct GHCheck: Decodable, Sendable {
    let name: String?
    let context: String?
    let workflowName: String?
    let status: String?
    let conclusion: String?
    let state: String?

    var displayName: String {
        name ?? context ?? workflowName ?? "Check"
    }

    var checkState: CheckState {
        let normalized = (conclusion ?? status ?? state ?? "").uppercased()
        if ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"].contains(normalized) {
            return .failed
        }
        if ["SUCCESS", "NEUTRAL", "SKIPPED"].contains(normalized) {
            return .success
        }
        return .pending
    }
}
