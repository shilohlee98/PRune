import AppKit
import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case code = "Code"
    var id: String { rawValue }
}

enum DetailFindCommand: String {
    case open
    case next
    case previous

    @MainActor
    static func send(_ command: Self) {
        NotificationCenter.default.post(
            name: .detailFindCommand,
            object: NSApp.keyWindow,
            userInfo: ["command": command.rawValue]
        )
    }
}

extension Notification.Name {
    static let detailFindCommand = Notification.Name("PRune.detailFindCommand")
}

private struct DetailFindMatch: Hashable {
    let anchor: String
    let filePath: String?

    init(_ anchor: String, filePath: String? = nil) {
        self.anchor = anchor
        self.filePath = filePath
    }
}

struct PullRequestDetailView: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest?
    @Binding var tab: DetailTab
    @State private var selectedCommitOID: String?
    @State private var commitsExpanded = true
    @State private var checksExpanded = true
    @State private var activityExpanded = true
    @State private var hoveredCommitOID: String?
    @State private var codeNavigationTarget: CodeNavigationTarget?
    @State private var detailWindowNumber: Int?
    @State private var isFindPresented = false
    @State private var findQuery = ""
    @State private var findIndex = 0
    @State private var findRequestID = UUID()
    @State private var findFocusRequestID = UUID()

    private var searchQuery: String {
        isFindPresented ? findQuery : ""
    }

    private var findMatches: [DetailFindMatch] {
        guard let pullRequest, !searchQuery.isEmpty else { return [] }
        return switch tab {
        case .summary: summaryFindMatches(for: pullRequest)
        case .code: codeFindMatches(for: pullRequest)
        }
    }

    private var activeFindMatch: DetailFindMatch? {
        findMatches.indices.contains(findIndex) ? findMatches[findIndex] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            GitHubFeedbackBanner()

            if store.isChangingListContext {
                PanelLoadingView(
                    message: tab == .summary ? "Loading summary…" : "Loading code…"
                )
            } else if let pullRequest {
                if tab == .summary {
                    ScrollViewReader { proxy in
                        ScrollView {
                            summaryView(pullRequest)
                        }
                        .scrollIndicators(.never)
                        .onChange(of: findRequestID) {
                            scrollToSummaryMatch(using: proxy)
                        }
                    }
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
        .overlay(alignment: .topTrailing) {
            if isFindPresented && !store.isChangingListContext {
                FloatingFindPanel(
                    query: $findQuery,
                    tab: tab,
                    resultCount: findMatches.count,
                    resultIndex: findIndex,
                    focusRequestID: findFocusRequestID,
                    onPrevious: { moveFind(by: -1) },
                    onNext: { moveFind(by: 1) },
                    onClose: closeFind
                )
                .frame(maxWidth: 320)
                .padding(10)
            }
        }
        .background(DetailWindowReader(windowNumber: $detailWindowNumber))
        .onReceive(NotificationCenter.default.publisher(for: .detailFindCommand)) { notification in
            guard let detailWindowNumber,
                  let requestedWindow = notification.object as? NSWindow,
                  requestedWindow.windowNumber == detailWindowNumber,
                  let rawCommand = notification.userInfo?["command"] as? String,
                  let command = DetailFindCommand(rawValue: rawCommand)
            else { return }
            switch command {
            case .open: openFind()
            case .next: moveFind(by: 1)
            case .previous: moveFind(by: -1)
            }
        }
        .onChange(of: findQuery) {
            findIndex = 0
            findRequestID = UUID()
        }
        .onChange(of: tab) {
            findIndex = 0
            findRequestID = UUID()
        }
        .onChange(of: findMatches.map(\.anchor)) {
            if findIndex >= findMatches.count { findIndex = 0 }
            findRequestID = UUID()
        }
        .onChange(of: pullRequest?.id) {
            tab = .summary
            selectedCommitOID = nil
            commitsExpanded = true
            checksExpanded = true
            activityExpanded = true
            codeNavigationTarget = nil
            closeFind()
        }
    }

    private func openFind() {
        guard pullRequest != nil else { return }
        isFindPresented = true
        findRequestID = UUID()
        findFocusRequestID = UUID()
    }

    private func closeFind() {
        isFindPresented = false
        findQuery = ""
        findIndex = 0
    }

    private func moveFind(by offset: Int) {
        guard isFindPresented else {
            openFind()
            return
        }
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + offset + findMatches.count) % findMatches.count
        findRequestID = UUID()
    }

    private func scrollToSummaryMatch(using proxy: ScrollViewProxy) {
        guard tab == .summary, let match = activeFindMatch else { return }
        if match.anchor.hasPrefix("summary-commit-") { commitsExpanded = true }
        if match.anchor.hasPrefix("summary-check-") { checksExpanded = true }
        if match.anchor.hasPrefix("summary-activity-") { activityExpanded = true }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(match.anchor, anchor: .center)
            }
        }
    }

    private func summaryFindMatches(for pullRequest: PullRequest) -> [DetailFindMatch] {
        var matches: [DetailFindMatch] = []
        func append(_ anchor: String, values: [String]) {
            if values.contains(where: { FindHighlight.contains(searchQuery, in: $0) }) {
                matches.append(DetailFindMatch(anchor))
            }
        }

        append("summary-title", values: [
            pullRequest.repositoryName, String(pullRequest.number),
            pullRequest.title, pullRequest.author,
        ])
        append("summary-facts", values: [
            pullRequest.branch, pullRequest.baseBranch,
            "\(pullRequest.comments) comments",
            pullRequest.checkState.rawValue, pullRequest.statusLabel,
        ])
        append("summary-description", values: [pullRequest.body])
        for commit in pullRequest.commits {
            append("summary-commit-\(commit.oid)", values: [
                commit.messageHeadline, commit.shortOID, commit.authorLogin,
            ])
        }
        for check in pullRequest.checks {
            append("summary-check-\(check.id)", values: [check.name, check.state.rawValue])
        }
        append("summary-activity-opened", values: [
            "\(pullRequest.author) opened this pull request",
        ])
        for comment in store.comments(for: pullRequest.id) ?? [] {
            append("summary-activity-\(comment.id)", values: [
                comment.authorLogin, comment.body,
            ])
        }
        return matches
    }

    private func codeFindMatches(for pullRequest: PullRequest) -> [DetailFindMatch] {
        guard let files = store.diffFiles(
            for: pullRequest.id,
            commitOID: selectedCommitOID
        ) else { return [] }
        var matches: [DetailFindMatch] = []
        let matchingComments = (store.comments(for: pullRequest.id) ?? []).filter { comment in
            comment.kind == .review
                && (FindHighlight.contains(searchQuery, in: comment.authorLogin)
                    || FindHighlight.contains(searchQuery, in: comment.body))
        }
        var foundCommentIDs: Set<String> = []
        for file in files {
            if FindHighlight.contains(searchQuery, in: file.path) {
                matches.append(DetailFindMatch(
                    CodeNavigationTarget.fileAnchor(for: file.path), filePath: file.path
                ))
            }
            for hunk in file.hunks {
                if FindHighlight.contains(searchQuery, in: hunk.header) {
                    matches.append(DetailFindMatch(
                        "hunk|\(file.path)|\(hunk.id)", filePath: file.path
                    ))
                }
                for line in hunk.lines {
                    if FindHighlight.contains(searchQuery, in: line.content),
                       let reviewLine = line.reviewLine {
                        matches.append(DetailFindMatch(
                            CodeNavigationTarget.lineAnchor(
                                path: file.path, line: reviewLine, side: line.reviewSide
                            ),
                            filePath: file.path
                        ))
                    }
                    for comment in matchingComments where comment.path == file.path {
                        guard let lineNumber = comment.line,
                              !foundCommentIDs.contains(comment.id)
                        else { continue }
                        let matchesLine = switch comment.diffSide?.uppercased() {
                        case "LEFT": line.oldLine == lineNumber
                        case "RIGHT": line.newLine == lineNumber
                        default: line.oldLine == lineNumber || line.newLine == lineNumber
                        }
                        guard matchesLine else { continue }
                        matches.append(DetailFindMatch(
                            "inline-comment|\(comment.id)", filePath: file.path
                        ))
                        foundCommentIDs.insert(comment.id)
                    }
                }
            }
        }
        return matches
    }

    private func summaryView(_ pullRequest: PullRequest) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString("\(pullRequest.repositoryName) · #\(pullRequest.number)")
                    ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.mutedText)
                    Text(FindHighlight.apply(searchQuery, to: AttributedString(pullRequest.title)))
                        .font(.system(size: 19, weight: .medium))
                        .textSelection(.enabled)
                    HStack(spacing: 7) {
                        AvatarView(
                            label: pullRequest.author,
                            imageURL: avatarURL(for: pullRequest.author, size: 42)
                        )
                        Text(FindHighlight.apply(
                            searchQuery,
                            to: AttributedString(pullRequest.author)
                        ))
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
            .id("summary-title")

            facts(pullRequest)
                .padding(.horizontal, 30)
                .padding(.bottom, 22)
                .id("summary-facts")

            Divider().overlay(Color.subtleBorder)

            EditableDescriptionSection(
                pullRequest: pullRequest,
                searchQuery: searchQuery,
                isFindTarget: activeFindMatch?.anchor == "summary-description"
            )
            .padding(30)
            .id("summary-description")

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
                .id("summary-activity-opened")

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
                                comment: comment,
                                searchQuery: searchQuery,
                                isFindTarget: activeFindMatch?.anchor
                                    == "summary-activity-\(comment.id)"
                            ) { path, line, side in
                                selectedCommitOID = nil
                                codeNavigationTarget = CodeNavigationTarget(
                                    path: path,
                                    line: line,
                                    side: side
                                )
                                tab = .code
                            }
                            .id("summary-activity-\(comment.id)")
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
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(pullRequest.branch.isEmpty ? "Loading…" : pullRequest.branch)
                    ))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.mutedText)
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(pullRequest.baseBranch.isEmpty ? "…" : pullRequest.baseBranch)
                    ))
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
                            ReviewerAvatar(login: reviewer)
                        }
                    }
                }
            }
            factRow(icon: "bubble.left", label: "Comments") {
                Text(FindHighlight.apply(
                    searchQuery,
                    to: AttributedString("\(pullRequest.comments) comments")
                ))
            }
            factRow(icon: "checkmark.circle", label: "Checks") {
                HStack(spacing: 7) {
                    StateDot(state: pullRequest.checkState)
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(pullRequest.checkState.rawValue)
                    ))
                        .foregroundStyle(StateDot(state: pullRequest.checkState).color)
                }
            }
            factRow(icon: "clock", label: "Status") {
                PullRequestStatusControl(
                    pullRequest: pullRequest,
                    searchQuery: searchQuery
                )
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
                    Text(FindHighlight.apply(searchQuery, to: AttributedString(check.name)))
                        .lineLimit(1)
                    Spacer()
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(check.state.rawValue)
                    ))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mutedText)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .id("summary-check-\(check.id)")

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
            Text(FindHighlight.apply(searchQuery, to: AttributedString(text)))
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
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(commit.messageHeadline)
                    ))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(FindHighlight.apply(
                            searchQuery,
                            to: AttributedString(commit.shortOID)
                        ))
                            .font(.system(size: 9.5, design: .monospaced))
                        Text(FindHighlight.apply(
                            searchQuery,
                            to: AttributedString(commit.authorLogin)
                        ))
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
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(hoveredCommitOID == commit.oid ? 0.07 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredCommitOID = commit.oid
            } else if hoveredCommitOID == commit.oid {
                hoveredCommitOID = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredCommitOID == commit.oid)
        .id("summary-commit-\(commit.oid)")
    }

    private func avatarURL(for login: String, size: CGFloat) -> URL? {
        guard !store.isShowingPreviewData else { return nil }
        return GitHubAvatarURL.forLogin(login, size: size)
    }

    private func codeView(_ pullRequest: PullRequest) -> some View {
        CodeReviewSection(
            pullRequest: pullRequest,
            selectedCommitOID: $selectedCommitOID,
            navigationTarget: codeNavigationTarget,
            searchQuery: searchQuery,
            findTargetID: activeFindMatch?.anchor,
            findTargetFilePath: activeFindMatch?.filePath,
            findRequestID: isFindPresented ? findRequestID : nil
        )
    }
}

private struct DetailWindowReader: NSViewRepresentable {
    @Binding var windowNumber: Int?

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { candidate in
            if windowNumber != candidate?.windowNumber {
                windowNumber = candidate?.windowNumber
            }
        }
        return view
    }

    func updateNSView(_ view: WindowTrackingView, context: Context) {
        view.onWindowChange = { candidate in
            if windowNumber != candidate?.windowNumber {
                windowNumber = candidate?.windowNumber
            }
        }
    }

    final class WindowTrackingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onWindowChange?(window)
            }
        }
    }
}

private struct FloatingFindPanel: View {
    @Binding var query: String
    let tab: DetailTab
    let resultCount: Int
    let resultIndex: Int
    let focusRequestID: UUID
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @State private var draftQuery = ""
    @FocusState private var isFieldFocused: Bool

    private var isPending: Bool { draftQuery != query }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)

                TextField("Find in \(tab.rawValue.lowercased())", text: $draftQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFieldFocused)
                    .onSubmit {
                        if isPending {
                            query = draftQuery
                        } else {
                            onNext()
                        }
                    }
                    .onExitCommand(perform: onClose)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1, height: 18)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel("Close find")
                .help("Close find (Esc)")
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 10) {
                Button(action: onPrevious) {
                    Image(systemName: "arrow.up")
                        .frame(width: 22, height: 22)
                }
                .disabled(resultCount == 0 || isPending)
                .accessibilityLabel("Previous result")
                .help("Previous result (⇧⌘G)")

                Button(action: onNext) {
                    Image(systemName: "arrow.down")
                        .frame(width: 22, height: 22)
                }
                .disabled(resultCount == 0 || isPending)
                .accessibilityLabel("Next result")
                .help("Next result (⌘G)")

                Spacer(minLength: 8)

                if !draftQuery.isEmpty {
                    Text(isPending ? "Searching…"
                        : "\(resultCount == 0 ? 0 : resultIndex + 1) / \(resultCount) results")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mutedText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
        }
        .foregroundStyle(Color.primary)
        .buttonStyle(.plain)
        .background(Color(red: 0.075, green: 0.078, blue: 0.085))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.13), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.38), radius: 12, y: 5)
        .onAppear {
            draftQuery = query
            DispatchQueue.main.async { isFieldFocused = true }
        }
        .onChange(of: focusRequestID) {
            isFieldFocused = true
        }
        .onChange(of: draftQuery) {
            if draftQuery.isEmpty { query = "" }
        }
        .task(id: draftQuery) {
            guard !draftQuery.isEmpty, isPending else { return }
            do {
                try await Task.sleep(for: .milliseconds(280))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            query = draftQuery
        }
    }
}

private struct ReviewerAvatar: View {
    let login: String
    @State private var isHovered = false

    var body: some View {
        AvatarView(
            label: login,
            imageURL: GitHubAvatarURL.forLogin(login, size: 42),
            showsHelp: false
        )
        .overlay {
            Circle()
                .stroke(Color.white.opacity(isHovered ? 0.65 : 0), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            if isHovered {
                Text(login)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    .offset(y: -34)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .zIndex(isHovered ? 1 : 0)
    }
}

private struct PullRequestStatusControl: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest
    let searchQuery: String

    @State private var pendingChange: PullRequestStatusChange?
    @State private var isStatusMenuPresented = false
    @State private var isStatusMenuHovered = false

    private var canEdit: Bool {
        pullRequest.scopes.contains(.authored)
            && pullRequest.status != .merged
            && !store.isShowingPreviewData
    }

    var body: some View {
        if canEdit {
            AppDropdown(
                isPresented: $isStatusMenuPresented,
                width: 188
            ) {
                HStack(spacing: 7) {
                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(pullRequest.statusLabel)
                    ))
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color.primary)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 27)
                .background(Color.white.opacity(
                    isStatusMenuHovered && !store.isPerformingMutation ? 0.14 : 0.08
                ))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(
                            isStatusMenuHovered && !store.isPerformingMutation ? 0.18 : 0.07
                        ), lineWidth: 0.7)
                }
                .contentShape(Capsule())
                .animation(.easeOut(duration: 0.12), value: isStatusMenuHovered)
            } menuContent: {
                VStack(spacing: 2) {
                    if pullRequest.status == .closed {
                        AppDropdownRow(isSelected: false) {
                            selectStatus(.reopen)
                        } content: {
                            Text("Reopen pull request")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                    } else {
                        AppDropdownRow(isSelected: pullRequest.isDraft) {
                            selectStatus(.draft)
                        } content: {
                            Text("Draft")
                                .font(.system(size: 11.5, weight: .medium))
                        }

                        AppDropdownRow(isSelected: !pullRequest.isDraft) {
                            selectStatus(.ready)
                        } content: {
                            Text("Ready for review")
                                .font(.system(size: 11.5, weight: .medium))
                        }

                        Divider()
                            .overlay(Color.subtleBorder)
                            .padding(.vertical, 4)

                        AppDropdownRow(
                            isSelected: false,
                            foregroundStyle: .red
                        ) {
                            selectStatus(.close)
                        } content: {
                            Text("Close pull request")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                    }
                }
            }
            .fixedSize()
            .onHover { isStatusMenuHovered = $0 }
            .disabled(store.isPerformingMutation)
            .alert(item: $pendingChange) { change in
                confirmationAlert(for: change)
            }
        } else {
            Text(FindHighlight.apply(
                searchQuery,
                to: AttributedString(pullRequest.statusLabel)
            ))
        }
    }

    private func selectStatus(_ change: PullRequestStatusChange) {
        isStatusMenuPresented = false
        switch change {
        case .draft:
            guard !pullRequest.isDraft else { return }
        case .ready:
            guard pullRequest.isDraft else { return }
        case .close:
            guard pullRequest.status == .open || pullRequest.status == .draft else { return }
        case .reopen:
            guard pullRequest.status == .closed else { return }
        }
        pendingChange = change
    }

    private func confirmationAlert(for change: PullRequestStatusChange) -> Alert {
        switch change {
        case .draft:
            Alert(
                title: Text("Convert this pull request to draft?"),
                message: Text("Reviewers will see that this pull request is not ready for review."),
                primaryButton: .default(Text("Convert to draft")) {
                    updateDraftState(isDraft: true)
                },
                secondaryButton: .cancel()
            )
        case .ready:
            Alert(
                title: Text("Mark this pull request ready for review?"),
                message: Text("Reviewers will be notified that this pull request is ready."),
                primaryButton: .default(Text("Mark ready")) {
                    updateDraftState(isDraft: false)
                },
                secondaryButton: .cancel()
            )
        case .close:
            Alert(
                title: Text("Close this pull request?"),
                message: Text("The pull request cannot be merged unless it is reopened."),
                primaryButton: .destructive(Text("Close pull request")) {
                    updateClosedState(isClosed: true)
                },
                secondaryButton: .cancel()
            )
        case .reopen:
            Alert(
                title: Text("Reopen this pull request?"),
                message: Text("The pull request will become active again."),
                primaryButton: .default(Text("Reopen pull request")) {
                    updateClosedState(isClosed: false)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func updateDraftState(isDraft: Bool) {
        Task {
            _ = await store.updateDraftState(for: pullRequest.id, isDraft: isDraft)
        }
    }

    private func updateClosedState(isClosed: Bool) {
        Task {
            _ = await store.updateClosedState(for: pullRequest.id, isClosed: isClosed)
        }
    }
}

private enum PullRequestStatusChange: String, Identifiable {
    case draft
    case ready
    case close
    case reopen

    var id: String { rawValue }
}
