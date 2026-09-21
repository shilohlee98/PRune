import Foundation
import Observation

struct OperationFeedback: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let succeeded: Bool
}

@Observable
@MainActor
final class PullRequestStore {
    var pullRequests: [PullRequest] = []
    var selectedID: PullRequest.ID?
    var scope: PullRequestScope = .authored
    var searchText = ""
    var statusFilter: PullRequestStatusFilter = .all
    var checkFilter: CheckState = .all
    var expandedRepositories: Set<String> = []
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var hasCompletedInitialLoad = false
    var isPerformingMutation = false
    var isLoadingGitHubAccounts = false
    var isSwitchingGitHubAccount = false
    var isShowingPreviewData = true
    var viewerLogin = ""
    var githubAccounts: [GitHubAccount] = []
    var errorMessage: String?
    var operationFeedback: OperationFeedback?

    private var diffs: [String: [PullRequestDiffFile]] = [:]
    private var loadingDiffKeys: Set<String> = []
    private var loadingDetailIDs: Set<PullRequest.ID> = []
    private var draftComments: [PullRequest.ID: [DraftReviewComment]] = [:]
    private var activityComments: [PullRequest.ID: [PullRequestComment]] = [:]
    private var loadingActivityIDs: Set<PullRequest.ID> = []
    private var pendingActivityReloadIDs: Set<PullRequest.ID> = []
    private var detailGeneration = 0
    private var diffGeneration = 0

    @ObservationIgnored
    private var prefetchTask: Task<Void, Never>?

    private let pullRequestPageSize = 20
    private let detailPrefetchLimit = 4
    private var pullRequestLimit = 20

    private let service = GitHubService()

    var filteredPullRequests: [PullRequest] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pullRequests.filter { pullRequest in
            let matchesScope = scope == .all || pullRequest.scopes.contains(scope)
            let matchesStatus = statusFilter.includes(pullRequest.status)
            let matchesCheck = checkFilter == .all || pullRequest.checkState == checkFilter
            let matchesSearch = query.isEmpty
                || pullRequest.title.lowercased().contains(query)
                || pullRequest.repositoryFullName.lowercased().contains(query)
                || pullRequest.branch.lowercased().contains(query)
                || String(pullRequest.number).contains(query)
            return matchesScope && matchesStatus && matchesCheck && matchesSearch
        }
    }

    var groupedPullRequests: [(repository: String, items: [PullRequest])] {
        Dictionary(grouping: filteredPullRequests, by: \.repositoryName)
            .map { (repository: $0.key, items: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.repository.localizedStandardCompare($1.repository) == .orderedAscending }
    }

    var selectedPullRequest: PullRequest? {
        pullRequests.first(where: { $0.id == selectedID })
    }

    var isLoadingDetails: Bool {
        selectedID.map(loadingDetailIDs.contains) ?? false
    }

    var activeGitHubAccount: GitHubAccount? {
        githubAccounts.first(where: \.isActive)
    }

    func refresh() async {
        guard !isLoading, !isLoadingMore else { return }
        let initialLimit = pullRequestPageSize
        canLoadMore = false
        prefetchTask?.cancel()
        detailGeneration += 1
        let generation = detailGeneration
        loadingDetailIDs.removeAll()
        loadingActivityIDs.removeAll()
        pendingActivityReloadIDs.removeAll()
        isLoading = true
        defer {
            isLoading = false
            hasCompletedInitialLoad = true
        }

        do {
            async let viewerLogin = service.fetchViewerLogin()
            async let githubAccounts = service.fetchAuthenticatedAccounts()
            let page = try await service.fetchPullRequests(
                scope: scope,
                status: statusFilter,
                limit: initialLimit
            )
            let livePullRequests = page.items
            self.viewerLogin = (try? await viewerLogin) ?? ""
            if let accounts = try? await githubAccounts {
                self.githubAccounts = accounts
            }
            diffGeneration += 1
            diffs.removeAll()
            loadingDiffKeys.removeAll()
            pullRequests = livePullRequests
            pullRequestLimit = initialLimit
            canLoadMore = page.hasMore
            activityComments.removeAll()
            expandedRepositories = Set(livePullRequests.map(\.repositoryName))
            isShowingPreviewData = false
            errorMessage = nil

            if !livePullRequests.contains(where: { $0.id == selectedID }) {
                selectedID = livePullRequests.first?.id
            }
            if let selectedID {
                await loadDetails(for: selectedID)
            }

            let selectedID = self.selectedID
            let prefetchIDs = livePullRequests
                .map(\.id)
                .filter { $0 != selectedID }
                .prefix(detailPrefetchLimit)
            prefetchTask = Task { [weak self] in
                await self?.prefetchDetails(ids: Array(prefetchIDs), generation: generation)
            }
        } catch {
            if pullRequests.isEmpty {
                isShowingPreviewData = true
            }
            errorMessage = "Could not load pull requests — \(error.localizedDescription)"
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextLimit = pullRequestLimit + pullRequestPageSize
        do {
            let page = try await service.fetchPullRequests(
                scope: scope,
                status: statusFilter,
                limit: nextLimit
            )
            let existing = Dictionary(uniqueKeysWithValues: pullRequests.map { ($0.id, $0) })
            pullRequests = page.items.map { item in
                guard let current = existing[item.id], current.detailsLoaded else { return item }
                var preserved = current
                preserved.scopes = item.scopes
                preserved.status = item.status
                preserved.isDraft = item.isDraft
                return preserved
            }
            pullRequestLimit = nextLimit
            canLoadMore = page.hasMore
            expandedRepositories.formUnion(page.items.map(\.repositoryName))
            isShowingPreviewData = false
            errorMessage = nil
        } catch {
            errorMessage = "Could not load more pull requests — \(error.localizedDescription)"
        }
    }

    func loadGitHubAccounts(showError: Bool = true) async {
        guard !isLoadingGitHubAccounts else { return }
        isLoadingGitHubAccounts = true
        defer { isLoadingGitHubAccounts = false }

        do {
            githubAccounts = try await service.fetchAuthenticatedAccounts()
        } catch {
            if showError {
                operationFeedback = OperationFeedback(
                    message: "Could not load GitHub accounts — \(error.localizedDescription)",
                    succeeded: false
                )
            }
        }
    }

    func switchGitHubAccount(to account: GitHubAccount) async {
        guard
            account.isAuthenticated,
            !account.isActive,
            !isLoading,
            !isLoadingGitHubAccounts,
            !isSwitchingGitHubAccount,
            !isPerformingMutation
        else { return }

        isSwitchingGitHubAccount = true
        defer { isSwitchingGitHubAccount = false }

        do {
            try await service.switchAccount(to: account)
            clearAccountSpecificState()
            operationFeedback = OperationFeedback(
                message: "Switched GitHub account to \(account.login).",
                succeeded: true
            )
            await refresh()
        } catch {
            operationFeedback = OperationFeedback(
                message: "Could not switch GitHub account — \(error.localizedDescription)",
                succeeded: false
            )
            await loadGitHubAccounts(showError: false)
        }
    }

    func select(_ pullRequest: PullRequest) {
        selectedID = pullRequest.id
        Task { await loadDetails(for: pullRequest.id) }
    }

    func loadDetails(for id: PullRequest.ID) async {
        guard
            let index = pullRequests.firstIndex(where: { $0.id == id }),
            !pullRequests[index].detailsLoaded,
            !loadingDetailIDs.contains(id)
        else { return }

        let generation = detailGeneration
        let pullRequest = pullRequests[index]
        loadingDetailIDs.insert(id)
        defer {
            if generation == detailGeneration {
                loadingDetailIDs.remove(id)
            }
        }

        do {
            let details = try await service.fetchDetails(for: pullRequest)
            guard generation == detailGeneration else { return }
            if let currentIndex = pullRequests.firstIndex(where: { $0.id == id }) {
                pullRequests[currentIndex] = details
            }
        } catch {
            guard generation == detailGeneration else { return }
            errorMessage = "Could not load PR details — \(error.localizedDescription)"
        }
    }

    private func prefetchDetails(ids: [PullRequest.ID], generation: Int) async {
        let batchSize = 4

        for batchStart in stride(from: 0, to: ids.count, by: batchSize) {
            guard !Task.isCancelled, generation == detailGeneration else { return }

            let batchEnd = min(batchStart + batchSize, ids.count)
            let batch = ids[batchStart..<batchEnd].compactMap { id in
                pullRequests.first(where: { $0.id == id && !$0.detailsLoaded })
            }
            guard !batch.isEmpty else { continue }

            loadingDetailIDs.formUnion(batch.map(\.id))
            let service = self.service
            let results = await withTaskGroup(
                of: (PullRequest.ID, PullRequest?).self,
                returning: [(PullRequest.ID, PullRequest?)].self
            ) { group in
                for pullRequest in batch {
                    group.addTask {
                        guard !Task.isCancelled else { return (pullRequest.id, nil) }
                        let details = try? await service.fetchDetails(for: pullRequest)
                        return (pullRequest.id, details)
                    }
                }

                var collected: [(PullRequest.ID, PullRequest?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            guard generation == detailGeneration else { return }
            for (id, details) in results {
                loadingDetailIDs.remove(id)
                guard
                    let details,
                    let index = pullRequests.firstIndex(where: { $0.id == id }),
                    !pullRequests[index].detailsLoaded
                else { continue }
                pullRequests[index] = details
            }
        }
    }

    func diffFiles(
        for id: PullRequest.ID,
        commitOID: String? = nil
    ) -> [PullRequestDiffFile]? {
        diffs[diffKey(for: id, commitOID: commitOID)]
    }

    func isLoadingDiff(for id: PullRequest.ID, commitOID: String? = nil) -> Bool {
        loadingDiffKeys.contains(diffKey(for: id, commitOID: commitOID))
    }

    func loadDiff(for id: PullRequest.ID, commitOID: String? = nil) async {
        await loadDetails(for: id)
        guard
            let pullRequest = pullRequests.first(where: { $0.id == id }),
            pullRequest.detailsLoaded
        else { return }

        let key = diffKey(for: id, commitOID: commitOID)
        let generation = diffGeneration
        guard diffs[key] == nil, !loadingDiffKeys.contains(key) else { return }

        loadingDiffKeys.insert(key)
        defer {
            if generation == diffGeneration {
                loadingDiffKeys.remove(key)
            }
        }
        do {
            let files = try await service.fetchDiff(for: pullRequest, commitOID: commitOID)
            guard
                generation == diffGeneration,
                diffKey(for: id, commitOID: commitOID) == key
            else { return }
            diffs[key] = files
        } catch {
            guard generation == diffGeneration else { return }
            operationFeedback = OperationFeedback(
                message: "Could not load the diff — \(error.localizedDescription)",
                succeeded: false
            )
        }
    }

    func draftReviewComments(
        for id: PullRequest.ID,
        commitOID: String? = nil
    ) -> [DraftReviewComment] {
        (draftComments[id] ?? []).filter { $0.commitOID == commitOID }
    }

    func addDraftComment(
        to id: PullRequest.ID,
        path: String,
        line: Int,
        side: String,
        body: String,
        commitOID: String? = nil
    ) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftComments[id, default: []].append(
            DraftReviewComment(
                path: path,
                line: line,
                side: side,
                body: trimmed,
                commitOID: commitOID
            )
        )
    }

    func removeDraftComment(from id: PullRequest.ID, commentID: UUID) {
        draftComments[id]?.removeAll(where: { $0.id == commentID })
    }

    func postInlineComment(
        on id: PullRequest.ID,
        path: String,
        line: Int,
        side: String,
        body: String,
        commitID: String? = nil
    ) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let comment = DraftReviewComment(
            path: path,
            line: line,
            side: side,
            body: trimmed,
            commitOID: commitID
        )
        let succeeded = await performMutation(successMessage: "Inline comment posted to GitHub.") {
            try await service.submitReview(
                on: pullRequest,
                event: .comment,
                body: "",
                comments: [comment],
                commitID: commitID
            )
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func comments(for id: PullRequest.ID) -> [PullRequestComment]? {
        activityComments[id]
    }

    func isLoadingActivity(for id: PullRequest.ID) -> Bool {
        loadingActivityIDs.contains(id)
    }

    func loadActivity(for id: PullRequest.ID, force: Bool = false) async {
        guard
            !isShowingPreviewData,
            let pullRequest = pullRequests.first(where: { $0.id == id }),
            force || activityComments[id] == nil
        else { return }

        if loadingActivityIDs.contains(id) {
            if force {
                pendingActivityReloadIDs.insert(id)
            }
            return
        }

        let generation = detailGeneration
        loadingActivityIDs.insert(id)

        do {
            let comments = try await service.fetchActivityComments(for: pullRequest)
            if generation == detailGeneration {
                activityComments[id] = comments
                if let index = pullRequests.firstIndex(where: { $0.id == id }) {
                    pullRequests[index].comments = comments.filter { $0.kind == .conversation }.count
                }
                if operationFeedback?.message.hasPrefix("Could not load comments") == true {
                    operationFeedback = nil
                }
            }
        } catch {
            if generation == detailGeneration {
                operationFeedback = OperationFeedback(
                    message: "Could not load comments — \(error.localizedDescription)",
                    succeeded: false
                )
            }
        }

        guard generation == detailGeneration else {
            loadingActivityIDs.remove(id)
            pendingActivityReloadIDs.remove(id)
            return
        }

        loadingActivityIDs.remove(id)
        if pendingActivityReloadIDs.remove(id) != nil {
            await loadActivity(for: id, force: true)
        }
    }

    func updateDescription(for id: PullRequest.ID, body: String) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        return await performMutation(successMessage: "Pull request description updated.") {
            try await service.updateDescription(of: pullRequest, body: body)
            if let index = pullRequests.firstIndex(where: { $0.id == id }) {
                pullRequests[index].body = body
            }
        }
    }

    func postComment(on id: PullRequest.ID, body: String) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let succeeded = await performMutation(successMessage: "Comment posted to GitHub.") {
            try await service.postComment(on: pullRequest, body: trimmed)
            if let index = pullRequests.firstIndex(where: { $0.id == id }) {
                pullRequests[index].comments += 1
            }
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func reply(
        to comment: PullRequestComment,
        on id: PullRequest.ID,
        body: String
    ) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let succeeded = await performMutation(successMessage: "Reply posted to GitHub.") {
            try await service.reply(to: comment, on: pullRequest, body: trimmed)
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func updateReviewThread(
        _ comment: PullRequestComment,
        on id: PullRequest.ID,
        resolved: Bool
    ) async -> Bool {
        guard
            pullRequests.contains(where: { $0.id == id }),
            comment.reviewThreadID != nil
        else { return false }

        let succeeded = await performMutation(
            successMessage: resolved ? "Review thread resolved." : "Review thread reopened."
        ) {
            try await service.updateReviewThread(comment, resolved: resolved)
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func editComment(
        _ comment: PullRequestComment,
        on id: PullRequest.ID,
        body: String
    ) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let succeeded = await performMutation(successMessage: "Comment updated on GitHub.") {
            try await service.updateComment(comment, on: pullRequest, body: trimmed)
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func deleteComment(
        _ comment: PullRequestComment,
        on id: PullRequest.ID
    ) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let succeeded = await performMutation(successMessage: "Comment deleted from GitHub.") {
            try await service.deleteComment(comment, on: pullRequest)
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func updateDraftState(for id: PullRequest.ID, isDraft: Bool) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let successMessage = isDraft
            ? "Pull request converted to draft."
            : "Pull request marked ready for review."
        return await performMutation(successMessage: successMessage) {
            try await service.updateDraftState(of: pullRequest, isDraft: isDraft)
            if let index = pullRequests.firstIndex(where: { $0.id == id }) {
                pullRequests[index].isDraft = isDraft
                pullRequests[index].status = isDraft ? .draft : .open
            }
        }
    }

    func submitReview(
        on id: PullRequest.ID,
        event: ReviewEvent,
        body: String,
        commitID: String? = nil
    ) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let comments = draftReviewComments(for: id, commitOID: commitID)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard event == .approve || !trimmedBody.isEmpty || !comments.isEmpty else { return false }

        let succeeded = await performMutation(successMessage: "\(event.rawValue) review submitted.") {
            try await service.submitReview(
                on: pullRequest,
                event: event,
                body: trimmedBody,
                comments: comments,
                commitID: commitID
            )
            let submittedIDs = Set(comments.map(\.id))
            draftComments[id]?.removeAll { submittedIDs.contains($0.id) }
        }
        if succeeded {
            await loadActivity(for: id, force: true)
        }
        return succeeded
    }

    func mergePullRequest(
        id: PullRequest.ID,
        method: PullRequestMergeMethod,
        automatically: Bool
    ) async -> Bool {
        guard
            let pullRequest = pullRequests.first(where: { $0.id == id }),
            !pullRequest.headRefOID.isEmpty,
            pullRequest.allowedMergeMethods.contains(method),
            automatically ? pullRequest.autoMergeAllowed : pullRequest.mergeBlockReason == nil
        else { return false }

        let successMessage = automatically
            ? "Auto-merge enabled with \(method.rawValue.lowercased())."
            : "Pull request merged with \(method.rawValue.lowercased())."
        let succeeded = await performMutation(successMessage: successMessage) {
            try await service.mergePullRequest(
                pullRequest,
                method: method,
                automatically: automatically
            )
        }
        if succeeded {
            await refresh()
        }
        return succeeded
    }

    func disableAutoMerge(for id: PullRequest.ID) async -> Bool {
        guard let pullRequest = pullRequests.first(where: { $0.id == id }) else { return false }
        let succeeded = await performMutation(successMessage: "Auto-merge disabled.") {
            try await service.disableAutoMerge(for: pullRequest)
        }
        if succeeded {
            await refresh()
        }
        return succeeded
    }

    func dismissOperationFeedback() {
        operationFeedback = nil
    }

    private func diffKey(for id: PullRequest.ID, commitOID: String?) -> String {
        if let commitOID {
            return "\(id)|commit:\(commitOID)"
        }

        let headRefOID = pullRequests
            .first(where: { $0.id == id })?
            .headRefOID ?? ""
        return "\(id)|head:\(headRefOID.isEmpty ? "pending" : headRefOID)"
    }

    private func clearAccountSpecificState() {
        prefetchTask?.cancel()
        detailGeneration += 1
        diffGeneration += 1
        pullRequests.removeAll()
        selectedID = nil
        viewerLogin = ""
        githubAccounts.removeAll()
        expandedRepositories.removeAll()
        diffs.removeAll()
        loadingDiffKeys.removeAll()
        loadingDetailIDs.removeAll()
        draftComments.removeAll()
        activityComments.removeAll()
        loadingActivityIDs.removeAll()
        pendingActivityReloadIDs.removeAll()
        isShowingPreviewData = false
        errorMessage = nil
    }

    private func performMutation(
        successMessage: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isShowingPreviewData, !isPerformingMutation else {
            if isShowingPreviewData {
                operationFeedback = OperationFeedback(
                    message: "GitHub editing is unavailable while preview data is shown.",
                    succeeded: false
                )
            }
            return false
        }

        isPerformingMutation = true
        defer { isPerformingMutation = false }
        do {
            try await operation()
            operationFeedback = OperationFeedback(message: successMessage, succeeded: true)
            return true
        } catch {
            operationFeedback = OperationFeedback(
                message: "GitHub rejected the action — \(error.localizedDescription)",
                succeeded: false
            )
            return false
        }
    }

    func toggleRepository(_ repository: String) {
        if expandedRepositories.contains(repository) {
            expandedRepositories.remove(repository)
        } else {
            expandedRepositories.insert(repository)
        }
    }
}
