import AppKit
import SwiftUI

struct GitHubFeedbackBanner: View {
    @Environment(PullRequestStore.self) private var store

    var body: some View {
        if let feedback = store.operationFeedback {
            HStack(spacing: 8) {
                Image(systemName: feedback.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(feedback.succeeded ? .green : .orange)
                Text(feedback.message)
                    .font(.system(size: 11))
                    .lineLimit(2)
                Spacer()
                Button {
                    store.dismissOperationFeedback()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.appIcon)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background((feedback.succeeded ? Color.green : Color.orange).opacity(0.08))
            .overlay(alignment: .bottom) { Divider().overlay(Color.subtleBorder) }
        }
    }
}

struct EditableDescriptionSection: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest
    let searchQuery: String
    let isFindTarget: Bool

    @State private var isEditing = false
    @State private var isExpanded = true
    @State private var draft = ""
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                PaneSectionHeader(
                    title: "Description",
                    isExpanded: isExpanded
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                }
                if pullRequest.scopes.contains(.authored) && !store.isShowingPreviewData {
                    Button {
                        draft = pullRequest.body
                        isEditing = true
                        isExpanded = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.appIcon)
                    .help("Edit description")
                    .disabled(isEditing || store.isPerformingMutation)
                }
            }

            if isExpanded && isEditing {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.appBackground)

                    TextEditor(text: $draft)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .background(Color.appBackground)
                }
                .frame(minHeight: 142, idealHeight: 160, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(red: 0.39, green: 0.45, blue: 0.66).opacity(0.8))
                )

                HStack {
                    Text("GitHub Markdown")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mutedText)
                    Spacer()
                    Button("Cancel") {
                        draft = pullRequest.body
                        isEditing = false
                    }
                    .buttonStyle(.appSecondary)
                    Button("Save") {
                        isConfirming = true
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(draft == pullRequest.body || store.isPerformingMutation)
                }
            } else if isExpanded && pullRequest.body.isEmpty {
                Text("No description provided.")
                    .foregroundStyle(Color.mutedText)
            } else if isExpanded {
                MarkdownDocumentView(
                    markdown: pullRequest.body,
                    searchQuery: searchQuery
                )
                    .textSelection(.enabled)
            }
        }
        .font(.system(size: 12))
        .onAppear { draft = pullRequest.body }
        .onChange(of: pullRequest.id) {
            draft = pullRequest.body
            isEditing = false
            isExpanded = true
        }
        .onChange(of: isFindTarget) {
            if isFindTarget { isExpanded = true }
        }
        .alert("Update pull request description?", isPresented: $isConfirming) {
            Button("Cancel", role: .cancel) {}
            Button("Update on GitHub") {
                Task {
                    if await store.updateDescription(for: pullRequest.id, body: draft) {
                        isEditing = false
                    }
                }
            }
        } message: {
            Text("This will replace the current description on GitHub.")
        }
    }
}

struct GeneralCommentComposer: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest

    @State private var bodyText = ""
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Add a comment")
                .font(.system(size: 12, weight: .medium))
            TextEditor(text: $bodyText)
                .font(.system(size: 11.5))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 82)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
            HStack {
                Text("Supports GitHub Markdown")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mutedText)
                Spacer()
                Button("Comment") {
                    isConfirming = true
                }
                .buttonStyle(.appPrimary)
                .disabled(
                    bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || store.isShowingPreviewData
                        || store.isPerformingMutation
                )
            }
        }
        .alert("Post this comment?", isPresented: $isConfirming) {
            Button("Cancel", role: .cancel) {}
            Button("Post to GitHub") {
                Task {
                    if await store.postComment(on: pullRequest.id, body: bodyText) {
                        bodyText = ""
                    }
                }
            }
        } message: {
            Text("The comment will be visible to everyone with access to this repository.")
        }
    }
}

struct CodeReviewSection: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest
    @Binding var selectedCommitOID: String?
    let navigationTarget: CodeNavigationTarget?
    let searchQuery: String
    let findTargetID: String?
    let findTargetFilePath: String?
    let findRequestID: UUID?

    @State private var inlineTarget: InlineCommentTarget?
    @State private var replyingCommentID: String?
    @State private var expandedResolvedCommentIDs: Set<String> = []
    @State private var diffLayout = DiffLayout.unified
    @State private var fileExpansionOverrides: [String: Bool] = [:]
    @State private var committedViewportWidth: CGFloat = 460
    @State private var isCommitMenuPresented = false
    @State private var isCommitSelectorHovered = false

    private var selectedCommit: PullRequestCommit? {
        pullRequest.commits.first { $0.oid == selectedCommitOID }
    }

    private var diffSelectionID: String {
        "\(pullRequest.id)|\(selectedCommitOID ?? "all")"
    }

    private var currentDiffFiles: [PullRequestDiffFile]? {
        store.diffFiles(for: pullRequest.id, commitOID: selectedCommitOID)
    }

    private var inlineReviewComments: [PullRequestComment] {
        (store.comments(for: pullRequest.id) ?? []).filter {
            $0.kind == .review && $0.path != nil && $0.line != nil
        }
    }

    private var diffTotals: (additions: Int, deletions: Int)? {
        guard selectedCommitOID != nil else {
            return (pullRequest.additions, pullRequest.deletions)
        }
        guard let files = store.diffFiles(
            for: pullRequest.id,
            commitOID: selectedCommitOID
        ) else { return nil }
        return (
            files.reduce(0) { $0 + $1.additions },
            files.reduce(0) { $0 + $1.deletions }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            reviewToolbar

            if store.isLoadingDiff(for: pullRequest.id, commitOID: selectedCommitOID)
                && currentDiffFiles == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading patch…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mutedText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if currentDiffFiles?.isEmpty == true {
                Text("No textual diff is available for this pull request.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VirtualizedDiffTable(
                    rows: virtualDiffRows(viewportWidth: committedViewportWidth),
                    contentRevision: "\(virtualContentRevision)|width:\(Int(committedViewportWidth))",
                    scrollRequestID: navigationScrollRequestID,
                    scrollTargetID: findTargetID ?? navigationAnchor
                ) { row in
                    AnyView(virtualDiffRowContent(row))
                }
                .background {
                    DebouncedWidthReader(width: $committedViewportWidth)
                }
            }

        }
        .task(id: diffSelectionID) {
            await store.loadDiff(for: pullRequest.id, commitOID: selectedCommitOID)
        }
        .task(id: "code-comments|\(pullRequest.id)") {
            await store.loadActivity(for: pullRequest.id)
        }
        .task(id: navigationTarget?.id) {
            guard let target = navigationTarget else { return }
            await store.loadDiff(for: pullRequest.id, commitOID: nil)
            fileExpansionOverrides[target.path] = true
        }
        .onChange(of: pullRequest.id) {
            inlineTarget = nil
            replyingCommentID = nil
            expandedResolvedCommentIDs.removeAll()
            fileExpansionOverrides.removeAll()
        }
        .onChange(of: selectedCommitOID) {
            inlineTarget = nil
            replyingCommentID = nil
            expandedResolvedCommentIDs.removeAll()
            fileExpansionOverrides.removeAll()
        }
        .onChange(of: findRequestID) {
            if let findTargetFilePath {
                fileExpansionOverrides[findTargetFilePath] = true
            }
            if let findTargetID, findTargetID.hasPrefix("inline-comment|") {
                expandedResolvedCommentIDs.insert(String(findTargetID.dropFirst(15)))
            }
        }
        .onChange(of: pullRequest.headRefOID) { oldHeadRefOID, newHeadRefOID in
            guard oldHeadRefOID != newHeadRefOID, !newHeadRefOID.isEmpty else { return }
            inlineTarget = nil
            replyingCommentID = nil
            expandedResolvedCommentIDs.removeAll()
            fileExpansionOverrides.removeAll()

            if let selectedCommitOID,
               !pullRequest.commits.contains(where: { $0.oid == selectedCommitOID }) {
                self.selectedCommitOID = nil
            } else {
                Task {
                    await store.loadDiff(
                        for: pullRequest.id,
                        commitOID: selectedCommitOID
                    )
                }
            }
        }
    }

    private var reviewToolbar: some View {
        GeometryReader { geometry in
            HStack(spacing: 6) {
                commitSelector(compact: geometry.size.width < 560)

                if let diffTotals {
                    HStack(spacing: 8) {
                        Text("+\(diffTotals.additions)")
                            .foregroundStyle(Color.green.opacity(0.78))
                        Text("−\(diffTotals.deletions)")
                            .foregroundStyle(Color.red.opacity(0.78))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 4)

                DiffToolbarActionButton(
                    accessibilityLabel: "Collapse all files",
                    systemImage: "rectangle.compress.vertical",
                    help: "Collapse all files",
                    isDisabled: currentDiffFiles?.isEmpty != false || allFilesCollapsed
                ) {
                    for file in currentDiffFiles ?? [] {
                        fileExpansionOverrides[file.path] = false
                    }
                }

                DiffToolbarActionButton(
                    accessibilityLabel: "Expand all files",
                    systemImage: "rectangle.expand.vertical",
                    help: "Expand all files",
                    isDisabled: currentDiffFiles?.isEmpty != false || !currentDiffFilesContainCollapsed
                ) {
                    for file in currentDiffFiles ?? [] {
                        fileExpansionOverrides[file.path] = true
                    }
                }

                DiffLayoutToggleButton(layout: $diffLayout)
            }
            .font(.system(size: 10.5))
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
        .frame(height: 36)
        .background(Color.panelBackground)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.subtleBorder)
        }
    }

    private var allFilesCollapsed: Bool {
        guard let files = currentDiffFiles, !files.isEmpty else { return false }
        return files.allSatisfy { isFileCollapsed($0.path) }
    }

    private var currentDiffFilesContainCollapsed: Bool {
        currentDiffFiles?.contains(where: { isFileCollapsed($0.path) }) == true
    }

    private func isFileCollapsed(_ path: String) -> Bool {
        if let isExpanded = fileExpansionOverrides[path] {
            return !isExpanded
        }
        return store.fileViewedState(for: pullRequest.id, path: path) == .viewed
    }

    private var navigationAnchor: String? {
        guard let navigationTarget, let files = currentDiffFiles else { return nil }
        return navigationTarget.anchor(in: files)
    }

    private var navigationScrollRequestID: String? {
        if let findRequestID, findTargetID != nil {
            return "find|\(findRequestID.uuidString)|width:\(Int(committedViewportWidth))"
        }
        guard let navigationTarget else { return nil }
        return "\(navigationTarget.id.uuidString)|width:\(Int(committedViewportWidth))"
    }

    private var virtualContentRevision: String {
        let collapsed = (currentDiffFiles ?? [])
            .filter { isFileCollapsed($0.path) }
            .map(\.path)
            .joined(separator: "|")
        let fileViews = (currentDiffFiles ?? []).map { file in
            let state = store.fileViewedState(for: pullRequest.id, path: file.path)
                .map { String($0.rawValue.prefix(1)) } ?? "?"
            let updating = store.isUpdatingFileViewedState(
                for: pullRequest.id, path: file.path
            )
            return "\(state)\(updating ? "1" : "0")"
        }.joined()
        let comments = inlineReviewComments.map {
            "\($0.id):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.isResolved)"
        }.joined(separator: "|")
        let expandedResolved = expandedResolvedCommentIDs.sorted().joined(separator: "|")
        return "\(diffSelectionID)|\(diffLayout.rawValue)|\(inlineTarget?.id ?? "")|\(replyingCommentID ?? "")|\(navigationTarget?.id.uuidString ?? "")|\(collapsed)|viewed:\(fileViews)|\(comments)|expanded:\(expandedResolved)|mutating:\(store.isPerformingMutation)|find:\(searchQuery)|target:\(findTargetID ?? "")"
    }

    private func virtualDiffRows(viewportWidth: CGFloat) -> [VirtualDiffRow] {
        guard let files = currentDiffFiles else { return [] }
        var rows: [VirtualDiffRow] = []

        for file in files {
            let fileAnchor = CodeNavigationTarget.fileAnchor(for: file.path)
            rows.append(
                VirtualDiffRow(
                    id: fileAnchor,
                    navigationIDs: [fileAnchor],
                    height: 34,
                    isGroup: true,
                    content: .fileHeader(file)
                )
            )
            guard !isFileCollapsed(file.path) else { continue }

            if file.hunks.isEmpty {
                rows.append(
                    VirtualDiffRow(
                        id: "binary|\(file.path)",
                        navigationIDs: [],
                        height: 48,
                        isGroup: false,
                        content: .binaryFile(file)
                    )
                )
                continue
            }

            for hunk in file.hunks {
                let hunkAnchor = "hunk|\(file.path)|\(hunk.id)"
                rows.append(
                    VirtualDiffRow(
                        id: hunkAnchor,
                        navigationIDs: [hunkAnchor],
                        height: 26,
                        isGroup: false,
                        content: .hunkHeader(hunk)
                    )
                )

                switch diffLayout {
                case .unified:
                    for line in hunk.lines {
                        let target = line.reviewLine.map {
                            InlineCommentTarget(
                                path: file.path,
                                line: $0,
                                side: line.reviewSide,
                                code: line.content,
                                kind: line.kind
                            )
                        }
                        let anchor = line.reviewLine.map {
                            CodeNavigationTarget.lineAnchor(
                                path: file.path,
                                line: $0,
                                side: line.reviewSide
                            )
                        } ?? line.id
                        rows.append(
                            VirtualDiffRow(
                                id: anchor,
                                navigationIDs: [anchor],
                                height: unifiedLineHeight(
                                    line,
                                    viewportWidth: viewportWidth
                                ) + (target?.id == inlineTarget?.id ? 152 : 0),
                                isGroup: false,
                                content: .unifiedLine(file, line)
                            )
                        )
                        if let target {
                            appendInlineComments(
                                for: target,
                                viewportWidth: viewportWidth,
                                to: &rows
                            )
                        }
                    }
                case .split:
                    for splitRow in hunk.splitRows {
                        let leftTarget = splitTarget(file: file, line: splitRow.left, side: "LEFT")
                        let rightTarget = splitTarget(file: file, line: splitRow.right, side: "RIGHT")
                        let navigationIDs = [leftTarget, rightTarget]
                            .compactMap { target in
                                target.map {
                                    CodeNavigationTarget.lineAnchor(
                                        path: $0.path,
                                        line: $0.line,
                                        side: $0.side
                                    )
                                }
                            }
                        let isSelected = [leftTarget, rightTarget]
                            .compactMap { $0 }
                            .contains { $0.id == inlineTarget?.id }
                        rows.append(
                            VirtualDiffRow(
                                id: "split|\(file.path)|\(splitRow.id)",
                                navigationIDs: navigationIDs,
                                height: splitLineHeight(
                                    splitRow,
                                    viewportWidth: viewportWidth
                                ) + (isSelected ? 152 : 0),
                                isGroup: false,
                                content: .splitLine(file, splitRow)
                            )
                        )
                        for target in [leftTarget, rightTarget].compactMap({ $0 }) {
                            appendInlineComments(
                                for: target,
                                viewportWidth: viewportWidth,
                                to: &rows
                            )
                        }
                    }
                }
            }
        }

        return rows
    }

    @ViewBuilder
    private func virtualDiffRowContent(_ row: VirtualDiffRow) -> some View {
        switch row.content {
        case let .fileHeader(file):
            diffFileHeader(file)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .background(Color.panelBackground)
        case let .hunkHeader(hunk):
            diffHunkHeader(hunk)
                .overlay(alignment: .leading) {
                    if findTargetID == row.id {
                        Rectangle().fill(Color.blue).frame(width: 3)
                    }
                }
        case let .unifiedLine(file, line):
            diffLine(file: file, line: line)
                .padding(.horizontal, 4)
        case let .splitLine(file, splitRow):
            splitDiffRow(file: file, row: splitRow)
                .padding(.horizontal, 4)
        case let .reviewComment(comment, target):
            alignedInlineReviewComment(comment, target: target)
                .padding(.horizontal, 4)
        case .binaryFile:
            Text("Binary or empty file change")
                .font(.system(size: 10))
                .foregroundStyle(Color.mutedText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.appBackground.opacity(0.82))
        }
    }

    @ViewBuilder
    private func alignedInlineReviewComment(
        _ comment: PullRequestComment,
        target: InlineCommentTarget
    ) -> some View {
        if diffLayout == .split {
            HStack(alignment: .top, spacing: 1) {
                splitInlineReviewCommentCell(
                    comment,
                    target: target,
                    cellSide: "LEFT"
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                splitInlineReviewCommentCell(
                    comment,
                    target: target,
                    cellSide: "RIGHT"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ZStack(alignment: .topLeading) {
                Color.appBackground
                GeometryReader { geometry in
                    inlineReviewComment(comment, side: target.side)
                        .frame(
                            width: min(760, max(0, geometry.size.width - 160)),
                            alignment: .leading
                        )
                        .offset(x: 80, y: 4)
                }
            }
            .clipped()
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DiffVisualStyle.accent(for: target.kind))
                    .frame(width: 3)
            }
        }
    }

    @ViewBuilder
    private func splitInlineReviewCommentCell(
        _ comment: PullRequestComment,
        target: InlineCommentTarget,
        cellSide: String
    ) -> some View {
        if target.side.uppercased() == cellSide {
            ZStack(alignment: .topLeading) {
                Color.appBackground
                GeometryReader { geometry in
                    inlineReviewComment(comment, side: target.side)
                        .frame(
                            width: max(0, geometry.size.width - 106),
                            alignment: .leading
                        )
                        .offset(x: 53, y: 4)
                }
            }
            .clipped()
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DiffVisualStyle.accent(for: target.kind))
                    .frame(width: 3)
            }
        } else {
            Color.appBackground.opacity(0.44)
        }
    }

    private func inlineReviewComment(
        _ comment: PullRequestComment,
        side: String
    ) -> some View {
        InlineReviewCommentView(
            comment: comment,
            side: side,
            searchQuery: searchQuery,
            isFindTarget: findTargetID == "inline-comment|\(comment.id)",
            isExpanded: !comment.isResolved
                || expandedResolvedCommentIDs.contains(comment.id),
            isReplying: replyingCommentID == comment.id,
            isInteractionDisabled: store.isShowingPreviewData || store.isPerformingMutation,
            onToggleExpanded: {
                guard comment.isResolved else { return }
                if expandedResolvedCommentIDs.contains(comment.id) {
                    expandedResolvedCommentIDs.remove(comment.id)
                    if replyingCommentID == comment.id {
                        replyingCommentID = nil
                    }
                } else {
                    expandedResolvedCommentIDs.insert(comment.id)
                }
            },
            onReply: {
                replyingCommentID = comment.id
            },
            onCancelReply: {
                replyingCommentID = nil
            },
            onPostReply: { body in
                let succeeded = await store.reply(
                    to: comment,
                    on: pullRequest.id,
                    body: body
                )
                if succeeded {
                    replyingCommentID = nil
                }
                return succeeded
            },
            onUpdateResolution: { resolved in
                await store.updateReviewThread(
                    comment,
                    on: pullRequest.id,
                    resolved: resolved
                )
            }
        )
    }

    private func appendInlineComments(
        for target: InlineCommentTarget,
        viewportWidth: CGFloat,
        to rows: inout [VirtualDiffRow]
    ) {
        let matchingComments = inlineReviewComments.filter { comment in
            guard comment.path == target.path, comment.line == target.line else { return false }
            guard let side = comment.diffSide?.uppercased() else { return true }
            return side == target.side.uppercased()
        }
        for comment in matchingComments {
            let anchor = "inline-comment|\(comment.id)"
            rows.append(
                VirtualDiffRow(
                    id: anchor,
                    navigationIDs: [anchor],
                    height: inlineCommentHeight(
                        comment,
                        isExpanded: !comment.isResolved
                            || expandedResolvedCommentIDs.contains(comment.id),
                        isReplying: replyingCommentID == comment.id,
                        availableWidth: diffLayout == .split
                            ? (viewportWidth - 9) / 2 - 106
                            : viewportWidth - 160
                    ),
                    isGroup: false,
                    content: .reviewComment(comment, target: target)
                )
            )
        }
    }

    private func inlineCommentHeight(
        _ comment: PullRequestComment,
        isExpanded: Bool,
        isReplying: Bool,
        availableWidth: CGFloat
    ) -> CGFloat {
        guard isExpanded else { return 42 }
        let explicitLines = max(1, comment.body.components(separatedBy: .newlines).count)
        let charactersPerLine = max(18, Int(max(120, availableWidth - 20) / 6.2))
        let wrappedLines = max(
            1,
            Int(ceil(Double(comment.body.count) / Double(charactersPerLine)))
        )
        let visibleLines = findTargetID == "inline-comment|\(comment.id)"
            ? max(explicitLines, wrappedLines)
            : min(6, max(explicitLines, wrappedLines))
        let hasThreadAction = comment.reviewThreadID != nil
            && ((comment.isResolved && comment.viewerCanUnresolve)
                || (!comment.isResolved && comment.viewerCanResolve))
        let commentHeight = 130
            + CGFloat(visibleLines * 15)
            + (hasThreadAction ? 45 : 0)
        return commentHeight + (isReplying ? 78 : 0) + 8
    }

    private func commitSelector(compact: Bool) -> some View {
        AppDropdown(
            isPresented: $isCommitMenuPresented,
            width: 500
        ) {
            HStack(spacing: 7) {
                Image(systemName: selectedCommit == nil ? "arrow.triangle.pull" : "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(Color.mutedText)
                    .frame(width: 14)
                Text(selectedCommit.map { "\($0.shortOID)  \($0.messageHeadline)" } ?? "All changes")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.mutedText)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 30)
            .appHeaderSurface(isHovered: isCommitSelectorHovered, restingOpacity: 0.045)
        } menuContent: {
            VStack(spacing: 4) {
                AppDropdownRow(isSelected: selectedCommitOID == nil) {
                    isCommitMenuPresented = false
                    selectedCommitOID = nil
                } content: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.pull")
                            .foregroundStyle(Color.mutedText)
                            .frame(width: 14)
                        Text("All changes")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                }

                Divider().overlay(Color.subtleBorder)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(pullRequest.commits) { commit in
                            AppDropdownRow(isSelected: selectedCommitOID == commit.oid) {
                                isCommitMenuPresented = false
                                selectedCommitOID = commit.oid
                            } content: {
                                HStack(spacing: 9) {
                                    Text(commit.shortOID)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Color.mutedText)
                                    Text(commit.messageHeadline)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(pullRequest.commits.count) * 36, 252))
            }
        }
        .frame(
            minWidth: compact ? 100 : 120,
            idealWidth: compact ? 125 : 160,
            maxWidth: compact ? 125 : 180
        )
        .onHover { isCommitSelectorHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isCommitSelectorHovered)
    }

    private func diffFileHeader(_ file: PullRequestDiffFile) -> some View {
        let isCollapsed = isFileCollapsed(file.path)
        let viewedState = store.fileViewedState(for: pullRequest.id, path: file.path)
        let isViewed = viewedState == .viewed
        let isUpdatingViewed = store.isUpdatingFileViewedState(
            for: pullRequest.id, path: file.path
        )

        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    toggleFile(file.path)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.mutedText)
                        .frame(width: 12)
                    DiffFileTypeBadge(path: file.path)
                    Text(FindHighlight.apply(searchQuery, to: AttributedString(file.path)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(-1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)

            HStack(spacing: 6) {
                Text("+\(file.additions)")
                    .foregroundStyle(Color.green.opacity(0.78))
                Text("−\(file.deletions)")
                    .foregroundStyle(Color.red.opacity(0.78))
            }
            .fixedSize()

            Spacer(minLength: 2)

            CopyPathButton(path: file.path)
                .fixedSize()

            Button {
                Task {
                    if await store.setFileViewed(!isViewed, for: file.path, on: pullRequest.id) {
                        fileExpansionOverrides[file.path] = nil
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if isUpdatingViewed {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: isViewed ? "checkmark.square.fill" : "square")
                    }
                    Text("Viewed")
                }
            }
            .buttonStyle(.appSecondaryCompact)
            .disabled(viewedState == nil || isUpdatingViewed || store.isPerformingMutation)
            .help(viewedState == nil
                ? "Viewed status is unavailable for this file"
                : isViewed ? "Mark file as unviewed" : "Mark file as viewed")
            .accessibilityLabel(isViewed ? "Mark file as unviewed" : "Mark file as viewed")
            .accessibilityValue(isViewed ? "On" : "Off")
            .fixedSize()
            .offset(y: -1)
        }
        .font(.system(size: 9.5, design: .monospaced))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(findTargetID == CodeNavigationTarget.fileAnchor(for: file.path)
            ? Color.blue.opacity(0.16) : Color.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.subtleBorder).frame(height: 1)
        }
    }

    private func diffHunkHeader(_ hunk: PullRequestDiffHunk) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text("···")
                    .font(.system(size: 9, weight: .bold))
                    .offset(y: -3)
            }
            .foregroundStyle(Color.white.opacity(0.60))
            .frame(width: 44, height: 26)
            .background(Color(red: 0.09, green: 0.19, blue: 0.35))
            .accessibilityHidden(true)

            Text(FindHighlight.apply(searchQuery, to: AttributedString(hunk.header)))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .background(Color(red: 0.09, green: 0.14, blue: 0.21))
    }

    private func unifiedLineHeight(
        _ line: PullRequestDiffLine,
        viewportWidth: CGFloat
    ) -> CGFloat {
        wrappedCodeHeight(
            line.content,
            availableWidth: viewportWidth - 86
        )
    }

    private func splitLineHeight(
        _ row: PullRequestSplitDiffRow,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let cellWidth = (viewportWidth - 9) / 2
        let codeWidth = cellWidth - 57
        return max(
            wrappedCodeHeight(row.left?.content ?? "", availableWidth: codeWidth),
            wrappedCodeHeight(row.right?.content ?? "", availableWidth: codeWidth)
        )
    }

    private func wrappedCodeHeight(_ source: String, availableWidth: CGFloat) -> CGFloat {
        DiffWrappedHeightCache.shared.height(
            for: source,
            availableWidth: availableWidth
        )
    }

    private func toggleFile(_ path: String) {
        fileExpansionOverrides[path] = isFileCollapsed(path)
    }

    private func diffLine(
        file: PullRequestDiffFile,
        line: PullRequestDiffLine
    ) -> some View {
        let target = line.reviewLine.map {
            InlineCommentTarget(
                path: file.path,
                line: $0,
                side: line.reviewSide,
                code: line.content,
                kind: line.kind
            )
        }
        let isSelected = target?.id == inlineTarget?.id
        let anchor = line.reviewLine.map {
            CodeNavigationTarget.lineAnchor(path: file.path, line: $0, side: line.reviewSide)
        } ?? line.id
        let isNavigationTarget = navigationTarget?.matches(path: file.path, line: line) == true
            || findTargetID == anchor

        return VStack(spacing: 0) {
            UnifiedDiffLineRow(
                line: line,
                isSelected: isSelected,
                isNavigationTarget: isNavigationTarget,
                searchQuery: searchQuery,
                canComment: target != nil
            ) {
                guard let target else { return }
                if inlineTarget?.id == target.id {
                    cancelInlineComment()
                } else {
                    inlineTarget = target
                }
            }

            if isSelected, let target {
                embeddedInlineCommentComposer(target)
            }
        }
        .id(anchor)
    }

    private func splitDiffRow(
        file: PullRequestDiffFile,
        row: PullRequestSplitDiffRow
    ) -> some View {
        let leftTarget = splitTarget(file: file, line: row.left, side: "LEFT")
        let rightTarget = splitTarget(file: file, line: row.right, side: "RIGHT")
        let selectedTarget = [leftTarget, rightTarget]
            .compactMap { $0 }
            .first { $0.id == inlineTarget?.id }

        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 1) {
                splitDiffCell(
                    file: file,
                    line: row.left,
                    side: "LEFT",
                    emphasizedRanges: row.intralineHighlights.old
                )
                splitDiffCell(
                    file: file,
                    line: row.right,
                    side: "RIGHT",
                    emphasizedRanges: row.intralineHighlights.new
                )
            }

            if let selectedTarget {
                embeddedInlineCommentComposer(selectedTarget)
            }
        }
    }

    @ViewBuilder
    private func embeddedInlineCommentComposer(
        _ target: InlineCommentTarget
    ) -> some View {
        if diffLayout == .split {
            HStack(alignment: .top, spacing: 1) {
                splitInlineCommentComposerCell(target, cellSide: "LEFT")
                    .frame(maxWidth: .infinity, alignment: .leading)
                splitInlineCommentComposerCell(target, cellSide: "RIGHT")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ZStack(alignment: .topLeading) {
                Color.appBackground
                GeometryReader { geometry in
                    inlineCommentComposer(target)
                        .frame(
                            width: min(760, max(0, geometry.size.width - 160)),
                            alignment: .leading
                        )
                        .offset(x: 80, y: 4)
                }
            }
            .clipped()
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DiffVisualStyle.accent(for: target.kind))
                    .frame(width: 3)
            }
        }
    }

    @ViewBuilder
    private func splitInlineCommentComposerCell(
        _ target: InlineCommentTarget,
        cellSide: String
    ) -> some View {
        if target.side.uppercased() == cellSide {
            ZStack(alignment: .topLeading) {
                Color.appBackground
                GeometryReader { geometry in
                    inlineCommentComposer(target)
                        .frame(
                            width: max(0, geometry.size.width - 106),
                            alignment: .leading
                        )
                        .offset(x: 53, y: 4)
                }
            }
            .clipped()
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DiffVisualStyle.accent(for: target.kind))
                    .frame(width: 3)
            }
        } else {
            Color.appBackground.opacity(0.44)
        }
    }

    @ViewBuilder
    private func splitDiffCell(
        file: PullRequestDiffFile,
        line: PullRequestDiffLine?,
        side: String,
        emphasizedRanges: [Range<Int>]
    ) -> some View {
        if let line,
            let lineNumber = side == "LEFT" ? line.oldLine : line.newLine
        {
            let target = InlineCommentTarget(
                path: file.path,
                line: lineNumber,
                side: side,
                code: line.content,
                kind: line.kind
            )
            let isSelected = inlineTarget?.id == target.id
            let anchor = CodeNavigationTarget.lineAnchor(
                path: file.path,
                line: lineNumber,
                side: side
            )
            let isNavigationTarget = navigationTarget?.matches(
                path: file.path,
                lineNumber: lineNumber,
                side: side
            ) == true || findTargetID == anchor

            SplitDiffLineCell(
                line: line,
                lineNumber: lineNumber,
                side: side,
                isSelected: isSelected,
                isNavigationTarget: isNavigationTarget,
                searchQuery: searchQuery,
                emphasizedRanges: emphasizedRanges
            ) {
                if isSelected {
                    cancelInlineComment()
                } else {
                    inlineTarget = target
                }
            }
            .id(anchor)
        } else {
            Color.appBackground.opacity(0.44)
                .frame(maxWidth: .infinity, minHeight: 24)
        }
    }

    private func splitTarget(
        file: PullRequestDiffFile,
        line: PullRequestDiffLine?,
        side: String
    ) -> InlineCommentTarget? {
        guard
            let line,
            let lineNumber = side == "LEFT" ? line.oldLine : line.newLine
        else { return nil }
        return InlineCommentTarget(
            path: file.path,
            line: lineNumber,
            side: side,
            code: line.content,
            kind: line.kind
        )
    }

    private func inlineCommentComposer(_ target: InlineCommentTarget) -> some View {
        let viewer = store.viewerLogin.isEmpty ? "You" : store.viewerLogin

        return InlineCommentComposerView(
            target: target,
            viewer: viewer,
            imageURL: store.isShowingPreviewData
                ? nil
                : GitHubAvatarURL.forLogin(viewer, size: 44),
            onCancel: cancelInlineComment,
            onPost: { body in
                await store.postInlineComment(
                    on: pullRequest.id,
                    path: target.path,
                    line: target.line,
                    side: target.side,
                    body: body,
                    commitID: selectedCommitOID
                )
            }
        )
        .id(target.id)
    }

    private func cancelInlineComment() {
        inlineTarget = nil
    }

}

private struct UnifiedDiffLineRow: View {
    let line: PullRequestDiffLine
    let isSelected: Bool
    let isNavigationTarget: Bool
    let searchQuery: String
    let canComment: Bool
    let onToggleComment: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                Text((line.newLine ?? line.oldLine).map(String.init) ?? "")
                    .frame(width: 48, height: 24, alignment: .trailing)
                    .foregroundStyle(DiffVisualStyle.lineNumberColor(for: line.kind))
                Text(DiffVisualStyle.marker(for: line.kind))
                    .frame(width: 20, height: 24, alignment: .center)
                    .foregroundStyle(DiffVisualStyle.markerColor(for: line.kind))
                SyntaxHighlightedCode(
                    source: line.content.isEmpty ? " " : line.content,
                    searchQuery: searchQuery
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onToggleComment) {
                Image(systemName: isSelected ? "xmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.86) : Color.white.opacity(0.74))
                    .frame(width: 24, height: 24)
                    .opacity(isHovering || isSelected ? 1 : 0)
            }
            .buttonStyle(.plain)
            .disabled(!canComment)
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .clipped()
        .background(isSelected || isNavigationTarget
            ? Color(red: 0.24, green: 0.40, blue: 0.54).opacity(0.78)
            : DiffVisualStyle.background(for: line.kind))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isNavigationTarget ? Color.blue.opacity(0.9) : DiffVisualStyle.accent(for: line.kind))
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct SplitDiffLineCell: View {
    let line: PullRequestDiffLine
    let lineNumber: Int
    let side: String
    let isSelected: Bool
    let isNavigationTarget: Bool
    let searchQuery: String
    let emphasizedRanges: [Range<Int>]
    let onToggleComment: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                Text(String(lineNumber))
                    .frame(width: 34, height: 24, alignment: .trailing)
                    .foregroundStyle(DiffVisualStyle.lineNumberColor(for: line.kind))
                Text(DiffVisualStyle.splitMarker(for: line.kind, side: side))
                    .frame(width: 22, height: 24, alignment: .center)
                    .foregroundStyle(DiffVisualStyle.markerColor(for: line.kind))
                SyntaxHighlightedCode(
                    source: line.content.isEmpty ? " " : line.content,
                    emphasizedRanges: emphasizedRanges,
                    emphasisColor: DiffVisualStyle.intralineBackground(for: line.kind),
                    searchQuery: searchQuery
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onToggleComment) {
                Image(systemName: isSelected ? "xmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .frame(width: 24, height: 24)
                    .opacity(isHovering || isSelected ? 1 : 0)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 10, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 24)
        .clipped()
        .background(isSelected || isNavigationTarget
            ? Color(red: 0.24, green: 0.40, blue: 0.54).opacity(0.78)
            : DiffVisualStyle.background(for: line.kind))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isNavigationTarget ? Color.blue.opacity(0.9) : DiffVisualStyle.accent(for: line.kind))
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private enum DiffVisualStyle {
    static func lineNumberColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: Color.white.opacity(0.42)
        case .addition: Color(red: 0.51, green: 0.85, blue: 0.57)
        case .deletion: Color(red: 0.96, green: 0.56, blue: 0.56)
        }
    }

    static func marker(for kind: DiffLineKind) -> String {
        switch kind {
        case .context: " "
        case .addition: "+"
        case .deletion: "−"
        }
    }

    static func splitMarker(for kind: DiffLineKind, side: String) -> String {
        switch kind {
        case .context: " "
        case .deletion: side == "LEFT" ? "−" : " "
        case .addition: side == "RIGHT" ? "+" : " "
        }
    }

    static func markerColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: Color.mutedText
        case .addition: Color(red: 0.42, green: 0.86, blue: 0.50)
        case .deletion: Color(red: 0.96, green: 0.44, blue: 0.48)
        }
    }

    static func accent(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: .clear
        case .addition: Color(red: 0.36, green: 0.82, blue: 0.43)
        case .deletion: Color(red: 0.91, green: 0.31, blue: 0.36)
        }
    }

    static func background(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context: Color.white.opacity(0.02)
        case .addition: Color(red: 0.15, green: 0.23, blue: 0.18)
        case .deletion: Color(red: 0.25, green: 0.16, blue: 0.17)
        }
    }

    static func intralineBackground(for kind: DiffLineKind) -> Color {
        switch kind {
        case .context:
            .clear
        case .addition:
            Color(red: 0.22, green: 0.37, blue: 0.27)
        case .deletion:
            Color(red: 0.40, green: 0.24, blue: 0.26)
        }
    }
}

private struct DiffToolbarActionButton: View {
    let accessibilityLabel: String
    let systemImage: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 30, height: 30)
                .appHeaderSurface(isHovered: isHovered, isEnabled: !isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DiffFileTypeBadge: View {
    let path: String

    private var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    private var tint: Color {
        switch fileExtension {
        case "ts", "tsx": Color(red: 0.40, green: 0.68, blue: 0.96)
        case "swift": Color(red: 0.98, green: 0.59, blue: 0.36)
        case "go": Color(red: 0.39, green: 0.80, blue: 0.85)
        case "md", "mdx": Color(red: 0.64, green: 0.68, blue: 0.95)
        case "json", "jsonc": Color(red: 0.92, green: 0.72, blue: 0.43)
        default: Color.secondaryText
        }
    }

    var body: some View {
        Group {
            if fileExtension.isEmpty {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
            } else {
                Text(fileExtension.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .frame(minWidth: 23)
        .frame(height: 18)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }
}

private struct CopyPathButton: View {
    let path: String

    @State private var isCopied = false
    @State private var isHovered = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            isCopied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                isCopied = false
            }
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(isCopied ? Color.green : Color.mutedText)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(isHovered ? 0.08 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isCopied ? "Path copied" : "Copy path: \(path)")
        .accessibilityLabel(isCopied ? "Path copied" : "Copy path")
        .animation(.easeOut(duration: 0.12), value: isHovered || isCopied)
    }
}

private struct DiffLayoutToggleButton: View {
    @Binding var layout: DiffLayout
    @State private var isHovering = false

    private var targetLayout: DiffLayout {
        layout == .unified ? .split : .unified
    }

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) {
                layout = targetLayout
            }
        } label: {
            DiffLayoutGlyph(layout: targetLayout)
                .frame(width: 30, height: 30)
                .appHeaderSurface(isHovered: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Switch to \(targetLayout.rawValue.lowercased()) diff")
        .accessibilityLabel("Switch to \(targetLayout.rawValue.lowercased()) diff")
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct DiffLayoutGlyph: View {
    let layout: DiffLayout

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .stroke(Color.white.opacity(0.48), lineWidth: 0.8)

            if layout == .split {
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.38, green: 0.76, blue: 0.90))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.82, green: 0.45, blue: 0.78))
                }
                .padding(3)
            } else {
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.42, green: 0.82, blue: 0.52))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.91, green: 0.42, blue: 0.48))
                }
                .padding(3)
            }
        }
        .frame(width: 14, height: 14)
    }
}

private enum DiffLayout: String, CaseIterable, Identifiable {
    case unified = "Unified"
    case split = "Split"

    var id: String { rawValue }
}

private struct InlineCommentTarget: Identifiable {
    var id: String { "\(path)-\(side)-\(line)" }
    let path: String
    let line: Int
    let side: String
    let code: String
    let kind: DiffLineKind
}

private struct InlineCommentComposerView: View {
    let target: InlineCommentTarget
    let viewer: String
    let imageURL: URL?
    let onCancel: () -> Void
    let onPost: (String) async -> Bool

    @State private var bodyText = ""
    @State private var isPosting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(label: viewer, size: 22, imageURL: imageURL)
                Text(viewer)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                Spacer()
                Text("Comment on line \(target.side == "LEFT" ? "L" : "R")\(target.line)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mutedText)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.appBackground.opacity(0.76))
                InlineCommentTextEditor(text: $bodyText)
                if bodyText.isEmpty {
                    Text("Leave a comment")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.mutedText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.10)))

            HStack {
                Text("Posts directly to GitHub")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.mutedText)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.appSecondary)
                Button("Post comment") {
                    let message = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !message.isEmpty, !isPosting else { return }
                    isPosting = true
                    Task {
                        let succeeded = await onPost(message)
                        isPosting = false
                        if succeeded {
                            onCancel()
                        }
                    }
                }
                .buttonStyle(.appPrimary)
                .disabled(
                    bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isPosting
                )
            }
        }
        .padding(10)
        .background(Color(red: 0.070, green: 0.074, blue: 0.082))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(red: 0.32, green: 0.48, blue: 0.66))
                .frame(width: 3)
        }
    }
}

private struct InlineReviewCommentView: View {
    let comment: PullRequestComment
    let side: String
    let searchQuery: String
    let isFindTarget: Bool
    let isExpanded: Bool
    let isReplying: Bool
    let isInteractionDisabled: Bool
    let onToggleExpanded: () -> Void
    let onReply: () -> Void
    let onCancelReply: () -> Void
    let onPostReply: (String) async -> Bool
    let onUpdateResolution: (Bool) async -> Bool

    @State private var replyText = ""
    @State private var isPostingReply = false
    @State private var isUpdatingResolution = false
    @State private var isCommentMenuPresented = false
    @State private var isCommentMenuHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            threadHeader

            if isExpanded {
                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        AvatarView(
                            label: comment.authorLogin,
                            size: 23,
                            imageURL: comment.authorAvatarURL
                                ?? GitHubAvatarURL.forLogin(comment.authorLogin, size: 46)
                        )
                        Text(FindHighlight.apply(
                            searchQuery,
                            to: AttributedString(comment.authorLogin)
                        ))
                            .font(.system(size: 11, weight: .semibold))
                        Text(comment.ageLabel)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.mutedText)
                        if comment.inReplyToID != nil {
                            badge("Reply", color: .green)
                        }
                        Spacer(minLength: 8)
                        commentMenu
                    }

                    Text(FindHighlight.apply(
                        searchQuery,
                        to: AttributedString(comment.body.isEmpty ? "No comment body" : comment.body)
                    ))
                        .font(.system(size: 11))
                        .foregroundStyle(comment.body.isEmpty ? Color.mutedText : Color.secondaryText)
                        .lineLimit(isFindTarget ? nil : 6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)

                Divider().overlay(Color.white.opacity(0.08))

                if isReplying {
                    replyComposer
                        .padding(8)
                } else if comment.viewerCanReply {
                    collapsedReplyField
                        .padding(8)
                }

                if hasThreadAction {
                    Divider().overlay(Color.white.opacity(0.08))
                    threadResolutionFooter
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.050, green: 0.057, blue: 0.068))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isFindTarget ? Color.yellow.opacity(0.8)
                    : comment.isResolved ? Color.white.opacity(0.16) : Color.blue.opacity(0.48))
        )
    }

    private var threadHeader: some View {
        Button {
            if comment.isResolved {
                onToggleExpanded()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.mutedText)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                Text("Comment on line")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondaryText)
                Text(lineReference)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                Spacer(minLength: 8)
                if comment.isResolved {
                    badge("Resolved", color: .green)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(comment.isResolved
            ? (isExpanded ? "Collapse resolved comment" : "Expand resolved comment")
            : "Unresolved comment")
        .background(Color.white.opacity(0.018))
    }

    private var collapsedReplyField: some View {
        Button {
            replyText = ""
            onReply()
        } label: {
            Text("Write a reply")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.mutedText)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(Color.appBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.16)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reply to this review thread")
        .disabled(isInteractionDisabled)
    }

    private var threadResolutionFooter: some View {
        HStack(spacing: 8) {
            Button {
                updateResolution(to: !comment.isResolved)
            } label: {
                Label(
                    comment.isResolved ? "Unresolve" : "Resolve comment",
                    systemImage: comment.isResolved ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .buttonStyle(.appSubtle)
            .disabled(isInteractionDisabled || isUpdatingResolution)

            Text(comment.isResolved
                ? "This review thread is resolved"
                : "Mark this review thread as resolved")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.mutedText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 44)
        .background(Color.white.opacity(0.018))
    }

    private var commentMenu: some View {
        AppDropdown(
            isPresented: $isCommentMenuPresented,
            width: 190
        ) {
            Image(systemName: "ellipsis")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.mutedText)
                .frame(width: 28, height: 28)
                .appToolbarSurface(
                    isHovered: isCommentMenuHovered,
                    isEnabled: !isInteractionDisabled
                )
        } menuContent: {
            VStack(spacing: 2) {
                if let webURL = comment.webURL {
                    AppDropdownRow(isSelected: false) {
                        isCommentMenuPresented = false
                        copyToPasteboard(webURL.absoluteString)
                    } content: {
                        Label("Copy link", systemImage: "link")
                            .font(.system(size: 11))
                    }

                    AppDropdownRow(isSelected: false) {
                        isCommentMenuPresented = false
                        NSWorkspace.shared.open(webURL)
                    } content: {
                        Label("Open on GitHub", systemImage: "arrow.up.forward")
                            .font(.system(size: 11))
                    }
                }

                AppDropdownRow(isSelected: false) {
                    isCommentMenuPresented = false
                    copyToPasteboard(comment.body)
                } content: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }

                if comment.viewerCanReply {
                    Divider().overlay(Color.subtleBorder)

                    AppDropdownRow(isSelected: false) {
                        isCommentMenuPresented = false
                        replyText = ""
                        onReply()
                    } content: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                            .font(.system(size: 11))
                    }
                }
            }
        }
        .fixedSize()
        .onHover { isCommentMenuHovered = $0 }
        .help("Comment actions")
        .disabled(isInteractionDisabled)
    }

    private var replyComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.appBackground.opacity(0.78))
                InlineCommentTextEditor(text: $replyText)
                if replyText.isEmpty {
                    Text("Write a reply")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.mutedText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.16)))

            HStack(spacing: 7) {
                Text("Posts to this GitHub review thread")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") {
                    replyText = ""
                    onCancelReply()
                }
                .buttonStyle(.appSecondary)

                Button(isPostingReply ? "Posting…" : "Reply") {
                    postReply()
                }
                .buttonStyle(.appPrimary)
                .disabled(isReplyDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isReplyDisabled: Bool {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isPostingReply
            || isInteractionDisabled
    }

    private var lineReference: String {
        let sidePrefix = side.uppercased() == "LEFT" ? "L" : "R"
        return "\(sidePrefix)\(comment.line ?? 0)"
    }

    private var hasThreadAction: Bool {
        comment.reviewThreadID != nil
            && ((comment.isResolved && comment.viewerCanUnresolve)
                || (!comment.isResolved && comment.viewerCanResolve))
    }

    private func updateResolution(to resolved: Bool) {
        guard !isUpdatingResolution else { return }
        isUpdatingResolution = true
        Task {
            _ = await onUpdateResolution(resolved)
            isUpdatingResolution = false
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func postReply() {
        let message = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isPostingReply else { return }
        isPostingReply = true
        Task {
            let succeeded = await onPostReply(message)
            isPostingReply = false
            if succeeded {
                replyText = ""
            }
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }
}

private struct InlineCommentTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 11.5)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineCommentTextEditor

        init(parent: InlineCommentTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private struct DebouncedWidthReader: View {
    @Binding var width: CGFloat
    @State private var pendingUpdate: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    scheduleUpdate(to: geometry.size.width, delay: .zero)
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    scheduleUpdate(to: newWidth, delay: .milliseconds(140))
                }
        }
        .allowsHitTesting(false)
        .onDisappear {
            pendingUpdate?.cancel()
        }
    }

    private func scheduleUpdate(
        to newWidth: CGFloat,
        delay: Duration
    ) {
        guard newWidth > 0 else { return }
        pendingUpdate?.cancel()
        pendingUpdate = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, abs(width - newWidth) > 0.5 else { return }
            width = newWidth
        }
    }
}

@MainActor
private final class DiffWrappedHeightCache {
    static let shared = DiffWrappedHeightCache()

    private struct Key: Hashable {
        let source: String
        let width: Int
    }

    private let maximumEntryCount = 30_000
    private let evictionCount = 6_000
    private var values: [Key: CGFloat] = [:]
    private var insertionOrder: [Key] = []

    func height(for source: String, availableWidth: CGFloat) -> CGFloat {
        // Round down so a cached measurement is never shorter than the real row.
        let width = max(1, Int(floor(availableWidth / 4)) * 4)
        let key = Key(source: source, width: width)
        if let cached = values[key] {
            return cached
        }

        let normalizedSource = source.replacingOccurrences(of: "\t", with: "    ")
        let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        let textStorage = NSTextStorage(
            string: normalizedSource.isEmpty ? " " : normalizedSource,
            attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: CGFloat(width),
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var visualLineCount = 0
        layoutManager.enumerateLineFragments(
            forGlyphRange: layoutManager.glyphRange(for: textContainer)
        ) { _, _, _, _, _ in
            visualLineCount += 1
        }
        let height = CGFloat(max(1, visualLineCount)) * 24
        values[key] = height
        insertionOrder.append(key)

        if values.count > maximumEntryCount {
            let expiredKeys = insertionOrder.prefix(evictionCount)
            for expiredKey in expiredKeys {
                values.removeValue(forKey: expiredKey)
            }
            insertionOrder.removeFirst(min(evictionCount, insertionOrder.count))
        }

        return height
    }
}

private struct VirtualDiffRow: Identifiable {
    enum Content {
        case fileHeader(PullRequestDiffFile)
        case hunkHeader(PullRequestDiffHunk)
        case unifiedLine(PullRequestDiffFile, PullRequestDiffLine)
        case splitLine(PullRequestDiffFile, PullRequestSplitDiffRow)
        case reviewComment(PullRequestComment, target: InlineCommentTarget)
        case binaryFile(PullRequestDiffFile)
    }

    let id: String
    let navigationIDs: [String]
    let height: CGFloat
    let isGroup: Bool
    let content: Content

    init(
        id: String,
        navigationIDs: [String],
        height: CGFloat,
        isGroup: Bool,
        content: Content
    ) {
        self.id = id
        self.navigationIDs = navigationIDs
        self.height = height
        self.isGroup = isGroup
        self.content = content
    }
}

private struct VirtualizedDiffTable: NSViewRepresentable {
    let rows: [VirtualDiffRow]
    let contentRevision: String
    let scrollRequestID: String?
    let scrollTargetID: String?
    let rowContent: (VirtualDiffRow) -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = DiffViewportScrollView()
        let clipView = VerticalOnlyClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        let verticalScroller = MinimalOverlayScroller()
        verticalScroller.controlSize = .small
        scrollView.verticalScroller = verticalScroller
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.gridColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 24
        tableView.floatsGroupRows = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 240
        tableView.addTableColumn(column)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.layouts = rows.map(VirtualRowLayout.init)
        context.coordinator.contentRevision = contentRevision
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if scrollView.contentView.bounds.origin.x != 0 {
            let verticalOffset = scrollView.contentView.bounds.origin.y
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: verticalOffset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if let tableView = coordinator.tableView,
            let column = tableView.tableColumns.first,
            scrollView.contentView.bounds.width > 0
        {
            let width = scrollView.contentView.bounds.width
            tableView.frame.size.width = width
            column.width = width
        }
        let layouts = rows.map(VirtualRowLayout.init)
        if coordinator.layouts != layouts || coordinator.contentRevision != contentRevision {
            coordinator.reloadPreservingScrollPosition(
                oldLayouts: coordinator.layouts,
                newLayouts: layouts
            ) {
                coordinator.layouts = layouts
                coordinator.contentRevision = contentRevision
            }
        }

        guard
            let scrollRequestID,
            scrollRequestID != coordinator.completedScrollRequestID,
            let scrollTargetID,
            let row = rows.firstIndex(where: { $0.navigationIDs.contains(scrollTargetID) })
        else { return }

        let tableView = coordinator.tableView
        let targetScrollView = coordinator.scrollView
        DispatchQueue.main.async { [weak coordinator, weak tableView, weak targetScrollView] in
            guard
                let coordinator,
                let tableView,
                let targetScrollView,
                row < tableView.numberOfRows
            else { return }
            coordinator.center(row: row, in: tableView, scrollView: targetScrollView)
            coordinator.completedScrollRequestID = scrollRequestID
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: VirtualizedDiffTable
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var layouts: [VirtualRowLayout] = []
        var contentRevision = ""
        var completedScrollRequestID: String?

        init(parent: VirtualizedDiffTable) {
            self.parent = parent
        }

        func center(row: Int, in tableView: NSTableView, scrollView: NSScrollView) {
            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            var targetBounds = scrollView.contentView.bounds
            targetBounds.origin.y = rowRect.midY - targetBounds.height / 2
            let constrainedBounds = scrollView.contentView.constrainBoundsRect(targetBounds)
            scrollView.contentView.scroll(to: constrainedBounds.origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func reloadPreservingScrollPosition(
            oldLayouts: [VirtualRowLayout],
            newLayouts: [VirtualRowLayout],
            updateState: () -> Void
        ) {
            guard let tableView, let scrollView else {
                updateState()
                tableView?.reloadData()
                return
            }

            let visibleRect = scrollView.documentVisibleRect
            let anchorRow = tableView.row(
                at: NSPoint(x: visibleRect.minX + 1, y: visibleRect.minY + 1)
            )
            let anchorID = oldLayouts.indices.contains(anchorRow)
                ? oldLayouts[anchorRow].id
                : nil
            let anchorOffset = oldLayouts.indices.contains(anchorRow)
                ? visibleRect.minY - tableView.rect(ofRow: anchorRow).minY
                : 0

            updateState()
            tableView.reloadData()
            tableView.layoutSubtreeIfNeeded()

            guard
                let anchorID,
                let newAnchorRow = newLayouts.firstIndex(where: { $0.id == anchorID }),
                newAnchorRow < tableView.numberOfRows
            else { return }

            var targetBounds = scrollView.contentView.bounds
            targetBounds.origin.y = tableView.rect(ofRow: newAnchorRow).minY + anchorOffset
            let constrainedBounds = scrollView.contentView.constrainBoundsRect(targetBounds)
            scrollView.contentView.scroll(to: constrainedBounds.origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rows.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard parent.rows.indices.contains(row) else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("virtual-diff-row")
            let content = parent.rowContent(parent.rows[row])

            if let hostingView = tableView.makeView(
                withIdentifier: identifier,
                owner: nil
            ) as? NSHostingView<AnyView> {
                hostingView.rootView = content
                hostingView.sizingOptions = []
                hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
                hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                return hostingView
            }

            let hostingView = NSHostingView(rootView: content)
            hostingView.identifier = identifier
            hostingView.sizingOptions = []
            hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return hostingView
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard parent.rows.indices.contains(row) else { return 24 }
            return parent.rows[row].height
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            parent.rows.indices.contains(row) && parent.rows[row].isGroup
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            false
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SeamlessDiffTableRowView()
        }
    }
}

private final class SeamlessDiffTableRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawSeparator(in dirtyRect: NSRect) {}
}

private final class DiffViewportScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard
            let tableView = documentView as? NSTableView,
            let column = tableView.tableColumns.first,
            contentView.bounds.width > 0
        else { return }

        let viewportWidth = contentView.bounds.width
        if abs(tableView.frame.width - viewportWidth) > 0.5 {
            tableView.frame.size.width = viewportWidth
        }
        if abs(column.width - viewportWidth) > 0.5 {
            column.width = viewportWidth
        }
    }
}

private final class VerticalOnlyClipView: NSClipView {
    override func layout() {
        super.layout()
        guard
            let tableView = documentView as? NSTableView,
            let column = tableView.tableColumns.first,
            bounds.width > 0
        else { return }

        let viewportWidth = bounds.width
        if abs(tableView.frame.width - viewportWidth) > 0.5 {
            tableView.frame.size.width = viewportWidth
        }
        if abs(column.width - viewportWidth) > 0.5 {
            column.width = viewportWidth
        }
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: 0, y: newOrigin.y))
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: 0, y: newOrigin.y))
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }
}

private final class MinimalOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {
        let knobRect = rect(for: .knob).insetBy(dx: 4, dy: 2)
        guard knobRect.width > 0, knobRect.height > 0 else { return }
        NSColor.white.withAlphaComponent(0.24).setFill()
        NSBezierPath(
            roundedRect: knobRect,
            xRadius: knobRect.width / 2,
            yRadius: knobRect.width / 2
        ).fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

private struct VirtualRowLayout: Equatable {
    let id: String
    let height: CGFloat
    let isGroup: Bool

    init(_ row: VirtualDiffRow) {
        id = row.id
        height = row.height
        isGroup = row.isGroup
    }
}
