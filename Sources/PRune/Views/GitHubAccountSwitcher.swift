import SwiftUI

@MainActor
struct GitHubAccountSwitcher: View {
    @Environment(PullRequestStore.self) private var store
    @Binding var isPopoverPresented: Bool
    @State private var isHovered = false

    private var displayedLogin: String {
        store.activeGitHubAccount?.login ?? store.viewerLogin
    }

    private var isBusy: Bool {
        store.isSwitchingGitHubAccount || store.isLoadingGitHubAccounts
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.subtleBorder)
            accountButton
        }
        .background(Color.panelBackground)
        .task {
            if store.githubAccounts.isEmpty {
                await store.loadGitHubAccounts(showError: false)
            }
        }
    }

    private var accountButton: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                AvatarView(
                    label: displayedLogin.isEmpty ? "GitHub" : displayedLogin,
                    size: 29,
                    imageURL: GitHubAvatarURL.forLogin(displayedLogin, size: 58)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedLogin.isEmpty ? "GitHub account" : displayedLogin)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(store.activeGitHubAccount?.host ?? "Choose an account")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.white.opacity(isHovered || isPopoverPresented ? 0.075 : 0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isSwitchingGitHubAccount || store.isPerformingMutation)
        .onHover { isHovered = $0 }
    }
}

@MainActor
struct GitHubAccountPopover: View {
    @Environment(PullRequestStore.self) private var store
    @Binding var isPresented: Bool

    private var isBusy: Bool {
        store.isSwitchingGitHubAccount || store.isLoadingGitHubAccounts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("GitHub accounts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text("Switch the account used by PRune and gh")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .overlay(Color.subtleBorder)

            accountList

            Divider()
                .overlay(Color.subtleBorder)

            Button {
                Task { await store.loadGitHubAccounts() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh accounts")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.elevatedBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.42), radius: 18, y: 8)
        .onExitCommand {
            isPresented = false
        }
    }

    @ViewBuilder
    private var accountList: some View {
        if store.githubAccounts.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("No authenticated accounts")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary)
                Text("Run `gh auth login` to add one.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mutedText)
            }
            .padding(12)
        } else {
            VStack(spacing: 3) {
                ForEach(store.githubAccounts) { account in
                    accountRow(account)
                }
            }
            .padding(6)
        }
    }

    private func accountRow(_ account: GitHubAccount) -> some View {
        Button {
            guard !account.isActive else {
                isPresented = false
                return
            }
            isPresented = false
            Task { await store.switchGitHubAccount(to: account) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if account.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.green)
                    }
                }
                .frame(width: 18)

                AvatarView(
                    label: account.login,
                    size: 28,
                    imageURL: GitHubAvatarURL.forLogin(account.login, size: 56)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.login)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(account.isAuthenticated ? account.host : "Authentication failed")
                        .font(.system(size: 10))
                        .foregroundStyle(account.isAuthenticated ? Color.mutedText : Color.red)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !account.isActive {
                    Text("Switch")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(account.isActive ? 0.055 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(
            !account.isAuthenticated
                || isBusy
                || store.isPerformingMutation
                || store.isLoading
        )
    }
}
