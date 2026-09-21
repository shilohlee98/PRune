import SwiftUI

struct ReviewSubmissionView: View {
    @Environment(PullRequestStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let pullRequest: PullRequest

    @State private var selectedEvent = ReviewEvent.comment
    @State private var bodyText = ""
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @FocusState private var isEditorFocused: Bool

    private var isOwnPullRequest: Bool {
        !store.viewerLogin.isEmpty
            && store.viewerLogin.caseInsensitiveCompare(pullRequest.author) == .orderedSame
    }

    private var pendingInlineCommentCount: Int {
        store.draftReviewComments(for: pullRequest.id).count
    }

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard !isSubmitting, !store.isPerformingMutation else { return false }
        guard !(isOwnPullRequest && selectedEvent != .comment) else { return false }

        switch selectedEvent {
        case .approve:
            return true
        case .comment, .requestChanges:
            return !trimmedBody.isEmpty || pendingInlineCommentCount > 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(Color.subtleBorder)

            VStack(alignment: .leading, spacing: 16) {
                commentEditor

                if let submissionError {
                    Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if pendingInlineCommentCount > 0 {
                    Label(
                        "Includes \(pendingInlineCommentCount) pending inline \(pendingInlineCommentCount == 1 ? "comment" : "comments")",
                        systemImage: "text.bubble"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ReviewEvent.allCases) { event in
                        reviewOption(event)
                    }
                }
            }
            .padding(18)

            Divider().overlay(Color.subtleBorder)

            footer
        }
        .frame(width: 610)
        .background(Color.panelBackground)
        .onAppear {
            isEditorFocused = true
        }
        .onChange(of: isOwnPullRequest) {
            if isOwnPullRequest, selectedEvent != .comment {
                selectedEvent = .comment
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Finish your review")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(pullRequest.repositoryName) · #\(pullRequest.number)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.appIcon)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var commentEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $bodyText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(7)
                .focused($isEditorFocused)

            if bodyText.isEmpty {
                Text("Add your review comment")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mutedText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 150)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isEditorFocused ? Color.blue.opacity(0.86) : Color.white.opacity(0.12),
                    lineWidth: isEditorFocused ? 1.5 : 1
                )
        )
    }

    private func reviewOption(_ event: ReviewEvent) -> some View {
        let unavailable = isOwnPullRequest && event != .comment

        return Button {
            guard !unavailable else { return }
            selectedEvent = event
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            selectedEvent == event ? Color.blue : Color.white.opacity(0.20),
                            lineWidth: 1.4
                        )
                        .frame(width: 16, height: 16)
                    if selectedEvent == event {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(unavailable ? Color.mutedText : Color.primary)
                    Text(optionDescription(for: event, unavailable: unavailable))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unavailable || isSubmitting)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                validationHint
                Spacer(minLength: 12)
                footerButtons
            }

            VStack(alignment: .trailing, spacing: 10) {
                validationHint
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    footerButtons
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }

    private var footerButtons: some View {
        HStack(spacing: 8) {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.appSubtle)
            .keyboardShortcut(.cancelAction)

            Button(submitButtonTitle) {
                submit()
            }
            .buttonStyle(.appPositive)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var validationHint: some View {
        if selectedEvent != .approve, trimmedBody.isEmpty, pendingInlineCommentCount == 0 {
            Text(selectedEvent == .requestChanges
                ? "Explain what needs to change before submitting."
                : "Add a comment before submitting.")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var submitButtonTitle: String {
        switch selectedEvent {
        case .comment: "Submit review"
        case .approve: "Approve"
        case .requestChanges: "Request changes"
        }
    }

    private func optionDescription(for event: ReviewEvent, unavailable: Bool) -> String {
        if unavailable {
            switch event {
            case .approve:
                return "Pull request authors can't approve their own pull requests."
            case .requestChanges:
                return "Pull request authors can't request changes on their own pull requests."
            case .comment:
                break
            }
        }

        switch event {
        case .comment:
            return "Submit general feedback without explicit approval."
        case .approve:
            return "Approve the proposed changes and allow them to be merged."
        case .requestChanges:
            return "Submit feedback that must be addressed before merging."
        }
    }

    private func submit() {
        guard canSubmit else { return }
        submissionError = nil
        isSubmitting = true
        Task {
            let succeeded = await store.submitReview(
                on: pullRequest.id,
                event: selectedEvent,
                body: trimmedBody
            )
            isSubmitting = false
            if succeeded {
                dismiss()
            } else {
                submissionError = store.operationFeedback?.message
                    ?? "GitHub did not accept this review."
            }
        }
    }
}
