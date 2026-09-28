<p align="center">
  <img src="AppBundle/Resources/PRuneIcon.png" alt="PRune icon" width="180">
</p>

<h1 align="center">PRune</h1>

<p align="center">
  A native GitHub pull request manager and review client for macOS.
</p>

## Features

- Browses All, Reviewing, and Authored pull requests grouped by repository, with incremental loading, search, pull-request status, and check-status filters
- Switches between GitHub accounts authenticated through the local `gh` CLI
- Shows pull request summaries, reviewers, checks, activity, commits, changed files, and merge blockers
- Opens all changes or a single commit in unified or split, syntax-highlighted diffs
- Filters diff files by extension, viewed status, and case-insensitive path text or globs such as `*.ts` and `src/*`; custom Include/Exclude options can be added, toggled, and deleted. Include matches any selected pattern; Exclude removes matching files, including when no Include options are selected
- Collapses individual files or the entire diff, copies file paths, opens the pull request on GitHub, and refreshes on demand
- Edits authored pull request descriptions, changes their status between Draft and Ready for review, and closes or reopens them
- Posts, replies to, quotes, edits, deletes, and locally hides comments
- Resolves and reopens review threads, including code context for outdated comments
- Drafts line-level comments and submits Comment, Approve, or Request changes reviews
- Merges with merge commits, squash, or rebase, and enables or disables auto-merge when GitHub allows it

Every action that writes to GitHub shows a native confirmation dialog first. Authentication and repository permissions come from the local `gh` CLI; the app does not store a GitHub token.

## Screenshots

### Pull request overview

<p align="center">
  <img src="docs/screenshots/pr-summary.png" alt="PRune pull request summary with fictional demo data" width="100%">
</p>

### Code review

<p align="center">
  <img src="docs/screenshots/code-review.png" alt="PRune inline code review with fictional demo data" width="100%">
</p>

### Submit a review

<p align="center">
  <img src="docs/screenshots/submit-review.png" alt="PRune submit review dialog with fictional demo data" width="85%">
</p>

### Merge options

<p align="center">
  <img src="docs/screenshots/merge-options.png" alt="PRune merge options with fictional demo data" width="100%">
</p>

### Switch GitHub accounts

<p align="center">
  <img src="docs/screenshots/switch-accounts.png" alt="PRune GitHub account switcher with fictional demo data" width="60%">
</p>

## Requirements

- GitHub CLI (`gh`): `brew install gh`
- Xcode, or compatible Xcode Command Line Tools with Swift 6.2 or newer

## Build and run

```sh
./scripts/build-app.sh &&
  open "build/PRune.app"
```

## License

Copyright 2026 Shiloh Lee. Licensed under the [Apache License 2.0](LICENSE).
