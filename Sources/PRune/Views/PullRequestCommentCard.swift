import AppKit
import SwiftUI

struct PullRequestCommentCard: View {
    @Environment(PullRequestStore.self) private var store
    let pullRequest: PullRequest
    let comment: PullRequestComment
    let onOpenCode: (String, Int?, String?) -> Void

    @State private var editorMode: CommentEditorMode?
    @State private var draft = ""
    @State private var isConfirmingDelete = false
    @State private var isExpanded: Bool
    @State private var isHidden = false
    @State private var isCommentMenuPresented = false

    init(
        pullRequest: PullRequest,
        comment: PullRequestComment,
        onOpenCode: @escaping (String, Int?, String?) -> Void
    ) {
        self.pullRequest = pullRequest
        self.comment = comment
        self.onOpenCode = onOpenCode
        _isExpanded = State(
            initialValue: !comment.isResolved && comment.body.count <= 900
        )
    }

    private var isOwnComment: Bool {
        !store.viewerLogin.isEmpty
            && store.viewerLogin.caseInsensitiveCompare(comment.authorLogin) == .orderedSame
    }

    private var isReply: Bool {
        comment.inReplyToID != nil
    }

    var body: some View {
        Group {
            if isHidden {
                hiddenRow
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .top, spacing: 10) {
                        if isReply {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.green.opacity(0.28))
                                .frame(width: 2)
                                .padding(.leading, 12)
                        }

                        AvatarView(
                            label: comment.authorLogin,
                            size: 27,
                            imageURL: comment.authorAvatarURL
                                ?? GitHubAvatarURL.forLogin(comment.authorLogin, size: 54)
                        )

                        header
                    }

                    if isExpanded {
                        if comment.kind == .review,
                            comment.inReplyToID == nil
                        {
                            ReviewCodeContextView(
                                comment: comment,
                                onOpenCode: onOpenCode
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            if comment.body.isEmpty {
                                Text("No comment body")
                                    .font(.system(size: 11.5))
                                    .italic()
                                    .foregroundStyle(Color.mutedText)
                            } else {
                                MarkdownDocumentView(markdown: comment.body)
                                    .textSelection(.enabled)
                            }

                            if editorMode != nil {
                                editor
                            }

                            if isReviewThreadRoot, editorMode == nil {
                                reviewThreadActions
                            }
                        }
                        .padding(.leading, commentContentIndent)
                    } else {
                        collapsedPreview
                            .padding(.leading, commentContentIndent)
                    }
                }
                .padding(13)
                .background(Color.elevatedBackground.opacity(isReply ? 0.34 : 0.58))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.subtleBorder))
                .padding(.leading, isReply ? 24 : 0)
            }
        }
        .alert("Delete this comment?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete from GitHub", role: .destructive) {
                Task {
                    _ = await store.deleteComment(comment, on: pullRequest.id)
                }
            }
        } message: {
            Text("This permanently deletes the comment from GitHub.")
        }
        .onChange(of: comment.isResolved) { _, isResolved in
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded = !isResolved
            }
            if isResolved {
                editorMode = nil
                draft = ""
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(comment.authorLogin)
                .font(.system(size: 11.5, weight: .semibold))

            if isReply {
                Text("reply")
                    .commentBadge(color: .green)
            }

            if comment.kind == .review {
                Text("inline")
                    .commentBadge(color: .purple)

                if comment.isResolved {
                    Text("Resolved")
                        .commentBadge(color: .green)
                }
            }

            Text(comment.ageLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.mutedText)

            if comment.isEdited {
                Text("edited")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.mutedText)
            }

            Spacer(minLength: 8)

            if comment.kind == .conversation, let webURL = comment.webURL {
                Button {
                    NSWorkspace.shared.open(webURL)
                } label: {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.appIcon)
                .help("Open comment on GitHub")
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
                if !isExpanded {
                    editorMode = nil
                    draft = ""
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.appIcon)
            .help(isExpanded ? "Collapse comment" : "Expand comment")

            commentMenu
        }
    }

    private var commentMenu: some View {
        AppDropdown(
            isPresented: $isCommentMenuPresented,
            width: 190
        ) {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
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
                }

                AppDropdownRow(isSelected: false) {
                    isCommentMenuPresented = false
                    copyToPasteboard(comment.body)
                } content: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }

                AppDropdownRow(isSelected: false) {
                    isCommentMenuPresented = false
                    beginReply(quoting: true)
                } content: {
                    Label("Quote reply", systemImage: "text.quote")
                        .font(.system(size: 11))
                }

                Divider().overlay(Color.subtleBorder)

                AppDropdownRow(isSelected: false) {
                    isCommentMenuPresented = false
                    beginReply(quoting: false)
                } content: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.system(size: 11))
                }

                if isOwnComment {
                    AppDropdownRow(isSelected: false) {
                        isCommentMenuPresented = false
                        isExpanded = true
                        editorMode = .edit
                        draft = comment.body
                    } content: {
                        Label("Edit", systemImage: "pencil")
                            .font(.system(size: 11))
                    }
                }

                AppDropdownRow(isSelected: false) {
                    isCommentMenuPresented = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        isHidden = true
                    }
                    editorMode = nil
                    draft = ""
                } content: {
                    Label("Hide", systemImage: "eye.slash")
                        .font(.system(size: 11))
                }

                if isOwnComment {
                    Divider().overlay(Color.subtleBorder)

                    AppDropdownRow(
                        isSelected: false,
                        foregroundStyle: .red
                    ) {
                        isCommentMenuPresented = false
                        isConfirmingDelete = true
                    } content: {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                }
            }
        }
        .fixedSize()
        .help("Comment actions")
        .disabled(store.isShowingPreviewData || store.isPerformingMutation)
    }

    private var collapsedPreview: some View {
        Text(collapsedSummary)
            .font(.system(size: 11))
            .foregroundStyle(Color.mutedText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hiddenRow: some View {
        HStack(spacing: 9) {
            AvatarView(
                label: comment.authorLogin,
                size: 21,
                imageURL: comment.authorAvatarURL
                    ?? GitHubAvatarURL.forLogin(comment.authorLogin, size: 42)
            )
            Text(comment.authorLogin)
                .font(.system(size: 10.5, weight: .medium))
            Text("comment hidden")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.mutedText)
            Spacer()
            Button("Show") {
                withAnimation(.easeOut(duration: 0.15)) {
                    isHidden = false
                }
            }
            .buttonStyle(.appSubtle)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(Color.elevatedBackground.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder))
        .padding(.leading, isReply ? 24 : 0)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(editorMode == .edit ? "Edit comment" : "Reply to \(comment.authorLogin)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                Spacer()
                Text("GitHub Markdown")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.mutedText)
            }

            TextEditor(text: $draft)
                .font(.system(size: 11.5))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 82)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.14)))

            HStack {
                Spacer()
                Button("Cancel") {
                    editorMode = nil
                    draft = ""
                }
                .buttonStyle(.appSecondary)

                Button(editorMode == .edit ? "Save" : "Reply") {
                    submit()
                }
                .buttonStyle(.appPrimary)
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (editorMode == .edit && draft == comment.body)
                        || store.isPerformingMutation
                )
            }
        }
    }

    private var reviewThreadActions: some View {
        HStack(spacing: 7) {
            if comment.viewerCanReply {
                Button {
                    beginReply(quoting: false)
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .buttonStyle(.appSubtle)
                .help("Reply to this review thread")
            }

            if comment.isResolved, comment.viewerCanUnresolve {
                Button {
                    updateReviewThread(resolved: false)
                } label: {
                    Label("Unresolve", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.appSubtle)
                .help("Reopen this review thread")
            } else if !comment.isResolved, comment.viewerCanResolve {
                Button {
                    updateReviewThread(resolved: true)
                } label: {
                    Label("Resolve", systemImage: "checkmark")
                }
                .buttonStyle(.appSubtle)
                .help("Resolve this review thread")
            }

            Spacer()
        }
        .disabled(store.isShowingPreviewData || store.isPerformingMutation)
    }

    private var quotedReply: String {
        let normalized = comment.body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let quote = normalized
            .components(separatedBy: "\n")
            .map { "> \($0)" }
            .joined(separator: "\n")
        return "\(quote)\n\n@\(comment.authorLogin) "
    }

    private var firstContentLine: String {
        comment.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? "Comment collapsed"
    }

    private var collapsedSummary: String {
        if comment.kind == .review, let path = comment.path {
            return path.split(separator: "/").last.map(String.init) ?? path
        }
        return comment.body.isEmpty ? "No comment body" : firstContentLine
    }

    private var commentContentIndent: CGFloat {
        isReply ? 61 : 37
    }

    private var isReviewThreadRoot: Bool {
        comment.kind == .review && comment.inReplyToID == nil
    }

    private func beginReply(quoting: Bool) {
        isExpanded = true
        editorMode = .reply
        draft = quoting
            ? quotedReply
            : (comment.kind == .conversation ? "@\(comment.authorLogin) " : "")
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func updateReviewThread(resolved: Bool) {
        Task {
            _ = await store.updateReviewThread(
                comment,
                on: pullRequest.id,
                resolved: resolved
            )
        }
    }

    private func submit() {
        guard let editorMode else { return }
        Task {
            let succeeded: Bool
            switch editorMode {
            case .reply:
                succeeded = await store.reply(to: comment, on: pullRequest.id, body: draft)
            case .edit:
                succeeded = await store.editComment(comment, on: pullRequest.id, body: draft)
            }
            if succeeded {
                self.editorMode = nil
                draft = ""
            }
        }
    }
}

private enum CommentEditorMode {
    case reply
    case edit
}

private extension View {
    func commentBadge(color: Color) -> some View {
        font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }
}
