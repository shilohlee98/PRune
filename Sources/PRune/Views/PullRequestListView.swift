import SwiftUI

struct PullRequestListView: View {
    @Environment(PullRequestStore.self) private var store
    @State private var isFilterPresented = false
    @State private var isFilterHovered = false

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                searchRow
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if !store.isChangingListContext, let errorMessage = store.errorMessage {
                    errorBanner(errorMessage)
                }

                if store.isChangingListContext {
                    PanelLoadingView(message: "Loading pull requests…")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(store.groupedPullRequests, id: \.repository) { group in
                                RepositoryGroupView(repository: group.repository, items: group.items)
                            }

                            if store.canLoadMore || store.isLoadingMore {
                                loadMoreButton
                                    .padding(.top, 12)
                            }

                            if store.filteredPullRequests.isEmpty && !store.isLoading {
                                ContentUnavailableView(
                                    "No pull requests",
                                    systemImage: "magnifyingglass",
                                    description: Text("Try another search or check status.")
                                )
                                .frame(height: 280)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, 20)
        }
        .background(Color.appBackground)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.mutedText)
                TextField("Search pull requests", text: Bindable(store).searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.mutedText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.elevatedBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))

            AppDropdown(
                isPresented: $isFilterPresented,
                width: 184
            ) {
                Image(systemName: "line.3.horizontal.decrease")
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(Color.elevatedBackground)
                            .overlay {
                                Circle().fill(Color.white.opacity(
                                    isFilterHovered && !store.isLoading && !store.isLoadingMore
                                        ? 0.10 : 0
                                ))
                            }
                    }
                    .overlay {
                        Circle().stroke(Color.white.opacity(
                            isFilterHovered && !store.isLoading && !store.isLoadingMore
                                ? 0.16 : 0
                        ), lineWidth: 0.8)
                    }
                    .contentShape(Circle())
                    .animation(.easeOut(duration: 0.12), value: isFilterHovered)
            } menuContent: {
                VStack(spacing: 2) {
                    Text("PULL REQUEST STATUS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)

                    ForEach(PullRequestStatusFilter.allCases) { status in
                        AppDropdownRow(isSelected: store.statusFilter == status) {
                            isFilterPresented = false
                            store.changeStatusFilter(to: status)
                        } content: {
                            HStack(spacing: 8) {
                                Image(systemName: statusIcon(status))
                                    .frame(width: 12)
                                    .foregroundStyle(Color.secondaryText)
                                Text(status.rawValue)
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                        }
                    }

                    Divider()
                        .overlay(Color.subtleBorder)
                        .padding(.vertical, 4)

                    Text("CHECKS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.bottom, 5)

                    ForEach(CheckState.allCases) { state in
                        AppDropdownRow(isSelected: store.checkFilter == state) {
                            isFilterPresented = false
                            store.checkFilter = state
                        } content: {
                            HStack(spacing: 8) {
                                StateDot(state: state)
                                Text(state.rawValue)
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                        }
                    }
                }
            }
            .fixedSize()
            .onHover { isFilterHovered = $0 }
            .disabled(store.isChangingListContext || store.isLoading || store.isLoadingMore)
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await store.loadMore() }
        } label: {
            Group {
                if store.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Load more")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .frame(minWidth: 76)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.elevatedBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isLoadingMore)
    }

    private func statusIcon(_ status: PullRequestStatusFilter) -> String {
        switch status {
        case .all: "circle.grid.2x2"
        case .open: "circle"
        case .draft: "pencil"
        case .closed: "xmark.circle"
        case .merged: "arrow.triangle.merge"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(message)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await store.refresh() }
            }
            .buttonStyle(.appSubtle)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.secondaryText)
        .padding(9)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 8)
    }

}

private struct RepositoryGroupView: View {
    @Environment(PullRequestStore.self) private var store
    let repository: String
    let items: [PullRequest]
    @State private var isHovered = false

    private var isExpanded: Bool {
        store.expandedRepositories.contains(repository)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    store.toggleRepository(repository)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.mutedText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 11)
                    Text(String(repository.prefix(1)).uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: 20, height: 20)
                        .background(Color.elevatedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.subtleBorder))
                    Text(repository)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.leading, 2)
                .frame(height: 29)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(isHovered ? 0.065 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)

            if isExpanded {
                ForEach(items) { pullRequest in
                    PullRequestRow(
                        pullRequest: pullRequest,
                        isSelected: store.selectedID == pullRequest.id
                    ) {
                        store.select(pullRequest)
                    }
                }
            }
        }
    }
}

private struct PullRequestRow: View {
    let pullRequest: PullRequest
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PullRequestGlyph(pullRequest: pullRequest, isSelected: isSelected)
                    .padding(.leading, 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pullRequest.title)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text("#\(pullRequest.number)")
                        if !pullRequest.branch.isEmpty {
                            Text("·")
                            Text(pullRequest.branch)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.36))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(pullRequest.ageLabel)
                    HStack(spacing: 5) {
                        Text("+\(pullRequest.additions)").foregroundStyle(.green.opacity(0.55))
                        Text("−\(pullRequest.deletions)").foregroundStyle(.red.opacity(0.55))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.34))
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.selectedBackground : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(isHovered ? (isSelected ? 0.04 : 0.065) : 0))
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
