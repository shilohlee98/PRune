import SwiftUI

struct ContentView: View {
    @Environment(PullRequestStore.self) private var store
    @State private var detailTab = DetailTab.summary
    @State private var reviewTarget: PullRequest?
    @State private var pendingMergeAction: PendingMergeAction?
    @State private var isReviewButtonHovered = false
    @State private var isMergeButtonHovered = false
    @State private var isRefreshButtonHovered = false
    @State private var isMergePopoverPresented = false
    @State private var isAccountPopoverPresented = false
    @State private var isSwitchingScope = false

    var body: some View {
        Group {
            if !store.hasCompletedInitialLoad
                || isSwitchingScope
                || (store.isLoading && store.pullRequests.isEmpty)
            {
                VStack(spacing: 0) {
                    standaloneTitleBar
                    initialLoadingView
                }
            } else if store.pullRequests.isEmpty, let errorMessage = store.errorMessage {
                VStack(spacing: 0) {
                    standaloneTitleBar
                    initialLoadFailureView(errorMessage)
                }
            } else {
                pullRequestWorkspace
            }
        }
        .background(Color.appBackground)
        .task {
            await store.refresh()
        }
        .sheet(item: $reviewTarget) { pullRequest in
            ReviewSubmissionView(pullRequest: pullRequest)
        }
        .alert(item: $pendingMergeAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .default(Text(action.confirmationTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var pullRequestWorkspace: some View {
        ZStack(alignment: .bottomLeading) {
            HSplitView {
                VStack(spacing: 0) {
                    leftTitleBar
                    PullRequestListView()
                    GitHubAccountSwitcher(isPopoverPresented: $isAccountPopoverPresented)
                }
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: 520)
                    .layoutPriority(0)

                VStack(spacing: 0) {
                    rightTitleBar
                        .zIndex(1)
                    PullRequestDetailView(
                        pullRequest: store.selectedPullRequest,
                        tab: $detailTab
                    )
                }
                    .frame(minWidth: 460, idealWidth: 820, maxWidth: .infinity)
                    .layoutPriority(1)
            }

            if isAccountPopoverPresented {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isAccountPopoverPresented = false
                    }
                    .zIndex(10)

                GitHubAccountPopover(isPresented: $isAccountPopoverPresented)
                    .padding(.leading, 10)
                    .padding(.bottom, 66)
                    .transition(.opacity)
                    .zIndex(11)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isAccountPopoverPresented)
    }

    private var leftTitleBar: some View {
        HStack(spacing: 0) {
            titleBarScopeTabs
            Spacer(minLength: 12)
        }
        .padding(.leading, 82)
        .padding(.trailing, 12)
        .frame(height: 38)
        .background {
            Color.panelBackground
            WindowDragRegion()
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.subtleBorder)
        }
    }

    private var rightTitleBar: some View {
        HStack(spacing: 0) {
            titleBarDetailTabs
            Spacer(minLength: 12)
            if let pullRequest = store.selectedPullRequest {
                Button {
                    reviewTarget = pullRequest
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.bubble")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Submit review")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .appToolbarSurface(
                        isHovered: isReviewButtonHovered,
                        isEnabled: !reviewButtonDisabled(for: pullRequest)
                    )
                }
                .buttonStyle(.plain)
                .disabled(reviewButtonDisabled(for: pullRequest))
                .onHover { isReviewButtonHovered = $0 }
                .help(reviewButtonHelp(for: pullRequest))
                .padding(.trailing, 8)

                mergeMenu(for: pullRequest)
                    .padding(.trailing, 8)
            }
            refreshButton
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background {
            Color.panelBackground
            WindowDragRegion()
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.subtleBorder)
        }
    }

    private func reviewButtonDisabled(for pullRequest: PullRequest) -> Bool {
        store.isShowingPreviewData
            || store.isPerformingMutation
            || pullRequest.headRefOID.isEmpty
    }

    private func reviewButtonHelp(for pullRequest: PullRequest) -> String {
        if store.isShowingPreviewData {
            return "Review actions are unavailable while preview data is shown"
        }
        if pullRequest.headRefOID.isEmpty {
            return "Loading pull request details"
        }
        return "Comment, approve, or request changes"
    }

    private func mergeMenu(for pullRequest: PullRequest) -> some View {
        let isBlocked = pullRequest.mergeBlockReason != nil
        let isDisabled = mergeMenuDisabled(for: pullRequest)

        return AppDropdown(isPresented: $isMergePopoverPresented, width: 260) {
            MergeMenuLabel(
                autoMergeEnabled: pullRequest.autoMergeEnabled,
                isBlocked: isBlocked
            )
            .appToolbarSurface(
                isHovered: isMergeButtonHovered,
                isEnabled: !isDisabled
            )
        } menuContent: {
            mergeActionsPopover(for: pullRequest)
        }
        .fixedSize()
        .disabled(isDisabled)
        .onHover { isMergeButtonHovered = $0 }
        .overlay(alignment: .bottomTrailing) {
            if isMergeButtonHovered
                && (isBlocked || isDisabled)
                && !isMergePopoverPresented
            {
                Text(mergeButtonHelp(for: pullRequest))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .offset(y: 38)
                    .allowsHitTesting(false)
            }
        }
        .help(mergeButtonHelp(for: pullRequest))
    }

    private func mergeActionsPopover(for pullRequest: PullRequest) -> some View {
        let mergeBlockReason = pullRequest.mergeBlockReason

        return VStack(alignment: .leading, spacing: 3) {
            Text("MERGE NOW")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.mutedText)
                .padding(.horizontal, 9)
                .padding(.top, 5)
                .padding(.bottom, 2)

            ForEach(PullRequestMergeMethod.allCases) { method in
                if pullRequest.allowedMergeMethods.contains(method) {
                    MergeActionRow(
                        title: method.rawValue,
                        detail: mergeBlockReason ?? "Merge the current head commit",
                        systemImage: mergeIcon(for: method),
                        isEnabled: mergeBlockReason == nil
                    ) {
                        selectMergeAction(.merge(method), for: pullRequest)
                    }
                }
            }

            if pullRequest.autoMergeEnabled || pullRequest.autoMergeAllowed {
                Divider()
                    .overlay(Color.subtleBorder)
                    .padding(.vertical, 4)

                Text("AUTO-MERGE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.mutedText)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 2)
            }

            if pullRequest.autoMergeEnabled {
                MergeActionRow(
                    title: "Disable auto-merge",
                    detail: "Keep this pull request manual",
                    systemImage: "stop.circle"
                ) {
                    selectMergeAction(.disableAutoMerge, for: pullRequest)
                }
            } else if pullRequest.autoMergeAllowed {
                ForEach(PullRequestMergeMethod.allCases) { method in
                    if pullRequest.allowedMergeMethods.contains(method) {
                        MergeActionRow(
                            title: "Enable with \(method.rawValue.lowercased())",
                            detail: "Merge when all requirements pass",
                            systemImage: "clock.arrow.circlepath"
                        ) {
                            selectMergeAction(.enableAutoMerge(method), for: pullRequest)
                        }
                    }
                }
            }
        }
    }

    private func selectMergeAction(
        _ kind: PendingMergeAction.Kind,
        for pullRequest: PullRequest
    ) {
        isMergePopoverPresented = false
        pendingMergeAction = PendingMergeAction(pullRequest: pullRequest, kind: kind)
    }

    private func mergeMenuDisabled(for pullRequest: PullRequest) -> Bool {
        let autoMergeAvailable = !pullRequest.isDraft
            && (pullRequest.autoMergeAllowed || pullRequest.autoMergeEnabled)

        return store.isShowingPreviewData
            || store.isPerformingMutation
            || pullRequest.headRefOID.isEmpty
            || pullRequest.allowedMergeMethods.isEmpty
            || (pullRequest.mergeBlockReason != nil && !autoMergeAvailable)
    }

    private func mergeButtonHelp(for pullRequest: PullRequest) -> String {
        if store.isShowingPreviewData { return "Merge actions are unavailable while preview data is shown" }
        if store.isPerformingMutation { return "Another pull request action is in progress" }
        if pullRequest.headRefOID.isEmpty { return "Loading merge status" }
        if pullRequest.allowedMergeMethods.isEmpty { return "This repository has no merge method enabled" }
        if let reason = pullRequest.mergeBlockReason { return reason }
        return pullRequest.autoMergeEnabled
            ? "Auto-merge is enabled"
            : "Merge or enable auto-merge"
    }

    private func mergeIcon(for method: PullRequestMergeMethod) -> String {
        switch method {
        case .merge: "arrow.triangle.merge"
        case .squash: "arrow.down.to.line.compact"
        case .rebase: "arrow.triangle.branch"
        }
    }

    private func perform(_ action: PendingMergeAction) {
        Task {
            switch action.kind {
            case let .merge(method):
                _ = await store.mergePullRequest(
                    id: action.pullRequestID,
                    method: method,
                    automatically: false
                )
            case let .enableAutoMerge(method):
                _ = await store.mergePullRequest(
                    id: action.pullRequestID,
                    method: method,
                    automatically: true
                )
            case .disableAutoMerge:
                _ = await store.disableAutoMerge(for: action.pullRequestID)
            }
        }
    }

    private var standaloneTitleBar: some View {
        HStack {
            Spacer()
            refreshButton
        }
        .padding(.leading, 82)
        .padding(.trailing, 14)
        .frame(height: 38)
        .background {
            Color.panelBackground
            WindowDragRegion()
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.subtleBorder)
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Group {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.mutedText)
                }
            }
            .frame(width: 28, height: 28)
            .appToolbarSurface(
                isHovered: isRefreshButtonHovered,
                isEnabled: !store.isLoading
            )
        }
        .buttonStyle(.plain)
        .onHover { isRefreshButtonHovered = $0 }
        .help("Refresh pull requests (⌘R)")
        .disabled(store.isLoading)
    }

    private var titleBarScopeTabs: some View {
        HStack(spacing: 3) {
            ForEach(PullRequestScope.allCases) { scope in
                TitleBarTab(
                    title: scope.rawValue,
                    isSelected: store.scope == scope,
                    isEnabled: !store.isLoading && !store.isLoadingMore
                ) {
                    guard store.scope != scope else { return }
                    isSwitchingScope = true
                    store.scope = scope
                    Task {
                        await store.refresh()
                        isSwitchingScope = false
                    }
                }
            }
        }
    }

    private var titleBarDetailTabs: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases) { item in
                TitleBarTab(title: item.rawValue, isSelected: detailTab == item, isEnabled: true) {
                    detailTab = item
                }
            }

            if store.isLoadingDetails {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 3)
            }
        }
    }

    private var initialLoadingView: some View {
        VStack(spacing: 13) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading pull requests…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondaryText)
            Text("Fetching the latest data from GitHub")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func initialLoadFailureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could not load pull requests", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await store.refresh() }
            }
            .buttonStyle(.appPrimary)
            .disabled(store.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TitleBarTab: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let showsHover = isHovered && isEnabled

        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(
                    isSelected ? Color.primary : (showsHover ? Color.secondaryText : Color.mutedText)
                )
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(
                            isSelected ? (showsHover ? 0.13 : 0.08) : (showsHover ? 0.06 : 0)
                        ))
                )
                .frame(minWidth: 44)
                .frame(height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: showsHover)
    }
}

private struct MergeMenuLabel: View {
    let autoMergeEnabled: Bool
    let isBlocked: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: autoMergeEnabled ? "clock.badge.checkmark" : "arrow.triangle.merge")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
            Text(autoMergeEnabled ? "Auto-merge" : "Merge")
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.mutedText)
        }
        .foregroundStyle(Color.primary.opacity(isBlocked ? 0.7 : 1))
        .padding(.horizontal, 10)
        .frame(minWidth: 98, minHeight: 28)
    }
}

private struct MergeActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isEnabled ? Color.green.opacity(0.88) : Color.mutedText
                    )
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.primary : Color.mutedText)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.mutedText)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(isEnabled && isHovered ? 0.10 : 0))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(isEnabled && isHovered ? 0.13 : 0), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = isEnabled && $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct PendingMergeAction: Identifiable {
    enum Kind {
        case merge(PullRequestMergeMethod)
        case enableAutoMerge(PullRequestMergeMethod)
        case disableAutoMerge
    }

    let id = UUID()
    let pullRequestID: PullRequest.ID
    let pullRequestNumber: Int
    let repositoryName: String
    let kind: Kind

    init(pullRequest: PullRequest, kind: Kind) {
        pullRequestID = pullRequest.id
        pullRequestNumber = pullRequest.number
        repositoryName = pullRequest.repositoryFullName
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .merge: "Merge pull request?"
        case .enableAutoMerge: "Enable auto-merge?"
        case .disableAutoMerge: "Disable auto-merge?"
        }
    }

    var message: String {
        let target = "\(repositoryName)#\(pullRequestNumber)"
        switch kind {
        case let .merge(method):
            return "\(target) will be merged using \(method.rawValue.lowercased()). This cannot be undone from PRune."
        case let .enableAutoMerge(method):
            return "\(target) will automatically merge using \(method.rawValue.lowercased()) when its requirements pass. If they already pass, GitHub may merge it immediately."
        case .disableAutoMerge:
            return "GitHub will stop automatically merging \(target)."
        }
    }

    var confirmationTitle: String {
        switch kind {
        case .merge: "Merge"
        case .enableAutoMerge: "Enable"
        case .disableAutoMerge: "Disable"
        }
    }
}
