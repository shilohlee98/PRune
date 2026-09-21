import AppKit
import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case code = "Code"
    var id: String { rawValue }
}

struct PullRequestDetailView: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest?
    @Binding var tab: DetailTab
    @State private var selectedCommitOID: String?
    @State private var commitsExpanded = true
    @State private var checksExpanded = true
    @State private var activityExpanded = true
    @State private var codeNavigationTarget: CodeNavigationTarget?

    var body: some View {
        VStack(spacing: 0) {
            GitHubFeedbackBanner()

            if let pullRequest {
                if tab == .summary {
                    ScrollView {
                        summaryView(pullRequest)
                    }
                    .scrollIndicators(.never)
                } else {
                    codeView(pullRequest)
                }
            } else {
                ContentUnavailableView(
                    "Select a pull request",
                    systemImage: "arrow.triangle.pull",
                    description: Text("Choose an item from a repository group.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.panelBackground)
        .onChange(of: pullRequest?.id) {
            tab = .summary
            selectedCommitOID = nil
            commitsExpanded = true
            checksExpanded = true
            activityExpanded = true
            codeNavigationTarget = nil
        }
    }

    private func summaryView(_ pullRequest: PullRequest) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(pullRequest.repositoryName) · #\(pullRequest.number)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.mutedText)
                    Text(pullRequest.title)
                        .font(.system(size: 19, weight: .medium))
                        .textSelection(.enabled)
                    HStack(spacing: 7) {
                        AvatarView(
                            label: pullRequest.author,
                            imageURL: avatarURL(for: pullRequest.author, size: 42)
                        )
                        Text(pullRequest.author)
                        Text("·")
                        Text(pullRequest.ageLabel)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                }

                Spacer(minLength: 12)

                Button {
                    NSWorkspace.shared.open(pullRequest.webURL)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.appIcon)
                .help("Open in browser")
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)

            facts(pullRequest)
                .padding(.horizontal, 30)
                .padding(.bottom, 22)

            Divider().overlay(Color.subtleBorder)

            EditableDescriptionSection(pullRequest: pullRequest)
            .padding(30)

            Divider().overlay(Color.subtleBorder)

            VStack(alignment: .leading, spacing: 12) {
                PaneSectionHeader(
                    title: "Commits",
                    count: pullRequest.commits.count,
                    isExpanded: commitsExpanded
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        commitsExpanded.toggle()
                    }
                }

                if commitsExpanded {
                    if pullRequest.commits.isEmpty {
                        Text(store.isLoadingDetails ? "Loading commits…" : "No commits reported.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mutedText)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(pullRequest.commits.enumerated()), id: \.element.id) { index, commit in
                                commitRow(commit)
                                if index < pullRequest.commits.count - 1 {
                                    Divider().overlay(Color.subtleBorder)
                                }
                            }
                        }
                        .background(Color.appBackground.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.subtleBorder))
                    }
                }
            }
            .padding(30)

            Divider().overlay(Color.subtleBorder)

            VStack(alignment: .leading, spacing: 16) {
                PaneSectionHeader(
                    title: "Checks",
                    count: pullRequest.checks.count,
                    isExpanded: checksExpanded
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        checksExpanded.toggle()
                    }
                }
                if checksExpanded {
                    if pullRequest.checks.isEmpty {
                        Text("No checks reported yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mutedText)
                    } else {
                        checksCard(pullRequest)
                    }
                }
            }
            .padding(30)

            Divider().overlay(Color.subtleBorder)

            activitySection(pullRequest)
            .padding(30)
            .padding(.bottom, 30)
        }
    }

    private func activitySection(_ pullRequest: PullRequest) -> some View {
        let comments = store.comments(for: pullRequest.id)
        let visibleCount = comments?.count ?? pullRequest.comments

        return VStack(alignment: .leading, spacing: 14) {
            PaneSectionHeader(
                title: "Activity",
                count: visibleCount + 1,
                isExpanded: activityExpanded
            ) {
                withAnimation(.easeOut(duration: 0.16)) {
                    activityExpanded.toggle()
                }
            }

            if activityExpanded {
                activityRow(
                    icon: "arrow.triangle.pull",
                    text: "\(pullRequest.author) opened this pull request"
                )

                if store.isLoadingActivity(for: pullRequest.id), comments == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading comments…")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mutedText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                } else if let comments {
                    if comments.isEmpty {
                        Text("No comments yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.mutedText)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(comments) { comment in
                            PullRequestCommentCard(
                                pullRequest: pullRequest,
                                comment: comment
                            ) { path, line, side in
                                selectedCommitOID = nil
                                codeNavigationTarget = CodeNavigationTarget(
                                    path: path,
                                    line: line,
                                    side: side
                                )
                                tab = .code
                            }
                        }
                    }
                } else {
                    Text("Comments are unavailable.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mutedText)
                        .padding(.vertical, 8)
                }

                GeneralCommentComposer(pullRequest: pullRequest)
                    .padding(.top, 5)
            }
        }
        .task(id: "\(pullRequest.id)|\(activityExpanded)") {
            if activityExpanded {
                await store.loadActivity(for: pullRequest.id)
            }
        }
    }

    private func facts(_ pullRequest: PullRequest) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 11) {
            factRow(icon: "point.topleft.down.to.point.bottomright.curvepath", label: "Merge") {
                HStack(spacing: 7) {
                    Text(pullRequest.branch.isEmpty ? "Loading…" : pullRequest.branch)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.mutedText)
                    Text(pullRequest.baseBranch.isEmpty ? "…" : pullRequest.baseBranch)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .help(pullRequest.baseBranch.isEmpty
                    ? "Loading merge target"
                    : "Merge \(pullRequest.branch) into \(pullRequest.baseBranch)")
            }
            factRow(icon: "person.2", label: "Reviewers") {
                HStack(spacing: 5) {
                    if pullRequest.reviewers.isEmpty {
                        Text("None")
                    } else {
                        ForEach(pullRequest.reviewers.prefix(6), id: \.self) { reviewer in
                            AvatarView(
                                label: reviewer,
                                imageURL: avatarURL(for: reviewer, size: 42)
                            )
                        }
                    }
                }
            }
            factRow(icon: "bubble.left", label: "Comments") {
                Text("\(pullRequest.comments) comments")
            }
            factRow(icon: "checkmark.circle", label: "Checks") {
                HStack(spacing: 7) {
                    StateDot(state: pullRequest.checkState)
                    Text(pullRequest.checkState.rawValue)
                        .foregroundStyle(StateDot(state: pullRequest.checkState).color)
                }
            }
            factRow(icon: "clock", label: "Status") {
                PullRequestStatusControl(pullRequest: pullRequest)
            }
        }
        .font(.system(size: 12))
    }

    private func factRow<Content: View>(
        icon: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Label(label, systemImage: icon)
                .foregroundStyle(Color.mutedText)
                .frame(width: 104, alignment: .leading)
            content()
                .foregroundStyle(Color.primary)
        }
    }

    private func checksCard(_ pullRequest: PullRequest) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(pullRequest.checks.enumerated()), id: \.element.id) { index, check in
                HStack(spacing: 9) {
                    Image(systemName: check.state == .success ? "checkmark.circle.fill" : check.state == .failed ? "xmark.circle.fill" : "clock.fill")
                        .foregroundStyle(StateDot(state: check.state).color)
                    Text(check.name)
                        .lineLimit(1)
                    Spacer()
                    Text(check.state.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mutedText)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .frame(height: 34)

                if index < pullRequest.checks.count - 1 {
                    Divider().overlay(Color.subtleBorder)
                }
            }
        }
        .background(Color.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.subtleBorder))
    }

    private func activityRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 22, height: 22)
                .background(Color.green.opacity(0.09))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(10)
        .background(Color.elevatedBackground.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder))
    }

    private func commitRow(_ commit: PullRequestCommit) -> some View {
        Button {
            selectedCommitOID = commit.oid
            tab = .code
        } label: {
            HStack(spacing: 10) {
                AvatarView(
                    label: commit.authorLogin,
                    size: 24,
                    imageURL: avatarURL(for: commit.authorLogin, size: 48)
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.messageHeadline)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(commit.shortOID)
                            .font(.system(size: 9.5, design: .monospaced))
                        Text(commit.authorLogin)
                        Text("·")
                        Text(commit.ageLabel)
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.mutedText)
                }
                Spacer()
                Text("Review")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.mutedText)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func avatarURL(for login: String, size: CGFloat) -> URL? {
        guard !store.isShowingPreviewData else { return nil }
        return GitHubAvatarURL.forLogin(login, size: size)
    }

    private func codeView(_ pullRequest: PullRequest) -> some View {
        CodeReviewSection(
            pullRequest: pullRequest,
            selectedCommitOID: $selectedCommitOID,
            navigationTarget: codeNavigationTarget
        )
    }
}

private struct PullRequestStatusControl: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest

    @State private var pendingChange: DraftStateChange?
    @State private var isStatusMenuPresented = false

    private var canEdit: Bool {
        pullRequest.scopes.contains(.authored) && !store.isShowingPreviewData
    }

    var body: some View {
        if canEdit {
            AppDropdown(
                isPresented: $isStatusMenuPresented,
                width: 172
            ) {
                HStack(spacing: 7) {
                    Text(pullRequest.statusLabel)
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 27)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                }
                .contentShape(Capsule())
            } menuContent: {
                VStack(spacing: 2) {
                    AppDropdownRow(isSelected: pullRequest.isDraft) {
                        selectStatus(isDraft: true)
                    } content: {
                        Text("Draft")
                            .font(.system(size: 11.5, weight: .medium))
                    }

                    AppDropdownRow(isSelected: !pullRequest.isDraft) {
                        selectStatus(isDraft: false)
                    } content: {
                        Text("Ready for review")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                }
            }
            .fixedSize()
            .disabled(store.isPerformingMutation)
            .alert(item: $pendingChange) { change in
                Alert(
                    title: Text(change.isDraft ? "Convert this pull request to draft?" : "Mark this pull request ready for review?"),
                    message: Text(change.isDraft
                        ? "Reviewers will see that this pull request is not ready for review."
                        : "Reviewers will be notified that this pull request is ready."),
                    primaryButton: .default(Text(change.isDraft ? "Convert to draft" : "Mark ready")) {
                        Task {
                            _ = await store.updateDraftState(
                                for: pullRequest.id,
                                isDraft: change.isDraft
                            )
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        } else {
            Text(pullRequest.statusLabel)
        }
    }

    private func selectStatus(isDraft: Bool) {
        isStatusMenuPresented = false
        guard isDraft != pullRequest.isDraft else { return }
        pendingChange = DraftStateChange(isDraft: isDraft)
    }
}

private struct DraftStateChange: Identifiable {
    let isDraft: Bool
    var id: Bool { isDraft }
}
