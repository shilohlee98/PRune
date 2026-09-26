import SwiftUI

struct DiffFileFilterDropdown: View {
    @Binding var filter: DiffFileFilter
    let files: [PullRequestDiffFile]
    let viewedFileCount: Int
    let visibleFiles: [PullRequestDiffFile]

    @State private var isPresented = false
    @State private var isHovered = false

    private var visibleTotals: (additions: Int, deletions: Int) {
        visibleFiles.reduce(into: (additions: 0, deletions: 0)) { totals, file in
            totals.additions += file.additions
            totals.deletions += file.deletions
        }
    }

    var body: some View {
        AppDropdown(isPresented: $isPresented, width: 320, allowsTextInput: true) {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                if filter.isActive {
                    HStack(spacing: 6) {
                        Text("\(visibleFiles.count)/\(files.count)")
                        Text("+\(visibleTotals.additions)")
                            .foregroundStyle(Color.green.opacity(0.78))
                        Text("−\(visibleTotals.deletions)")
                            .foregroundStyle(Color.red.opacity(0.78))
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(filter.isActive ? Color.primary : Color.secondaryText)
            .padding(.horizontal, filter.isActive ? 8 : 0)
            .frame(minWidth: 30, minHeight: 30)
            .appHeaderSurface(
                isHovered: isHovered,
                restingOpacity: filter.isActive ? 0.075 : 0
            )
        } menuContent: {
            DiffFileFilterMenu(filter: $filter, files: files, viewedFileCount: viewedFileCount)
        }
        .onHover { isHovered = $0 }
        .help("Filter files by path, extension, or viewed status")
        .accessibilityLabel("Filter files")
        .accessibilityValue(filter.isActive
            ? "\(visibleFiles.count) of \(files.count) files, \(visibleTotals.additions) additions, \(visibleTotals.deletions) deletions"
            : "All files")
    }
}

private struct DiffFileFilterMenu: View {
    @Binding var filter: DiffFileFilter
    let files: [PullRequestDiffFile]
    let viewedFileCount: Int

    @FocusState private var isPathFocused: Bool

    private var extensions: [(key: String, count: Int)] {
        Dictionary(grouping: files) { DiffFileFilter.extensionKey(for: $0.path) }
            .map { (key: $0.key, count: $0.value.count) }
            .sorted { $0.key < $1.key }
    }

    private var allOptionsSelected: Bool {
        filter.includesViewed && filter.includesUnviewed
            && extensions.allSatisfy { !filter.hiddenExtensions.contains($0.key) }
            && filter.pathOptions.allSatisfy(\.isSelected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle("FILTER FILES")
                Spacer()
                Button(allOptionsSelected ? "Deselect all" : "Select all") {
                    let selectAll = !allOptionsSelected
                    filter.hiddenExtensions = selectAll ? [] : Set(extensions.map(\.key))
                    filter.includesViewed = selectAll
                    filter.includesUnviewed = selectAll
                    for index in filter.pathOptions.indices {
                        filter.pathOptions[index].isSelected = selectAll
                    }
                }
                    .buttonStyle(.appSecondaryCompact)
            }

            DiffFileFilterModePicker(mode: $filter.pathQueryMode)
                .padding(.horizontal, 4)

            HStack(spacing: 4) {
                TextField("Path or glob, e.g. src/ or *.ts", text: $filter.pathQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(9)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(isPathFocused ? 0.25 : 0.10), lineWidth: 1)
                    }
                    .focused($isPathFocused)
                    .onSubmit { addPathOption() }
                    .accessibilityLabel("Filter file path")

                Button("Add") { addPathOption() }
                    .buttonStyle(.appSecondaryCompact)
                    .disabled(filter.pathQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add the entered path or glob as a filter option")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            if !filter.pathOptions.isEmpty {
                sectionTitle("CUSTOM FILTERS")
                Text("Include matches any. Exclude always removes.")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mutedText)
                    .padding(.horizontal, 10)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach($filter.pathOptions) { $option in
                            HStack(spacing: 2) {
                                AppDropdownRow(isSelected: option.isSelected) {
                                    option.isSelected.toggle()
                                } content: {
                                    optionLabel(option.query, count: files.filter {
                                        DiffFileFilter.matchesPath($0.path, query: option.query)
                                    }.count)
                                }
                                .accessibilityLabel("\(option.mode.title) filter: \(option.query)")

                                Button {
                                    option.mode = option.mode == .include ? .exclude : .include
                                } label: {
                                    Text(option.mode.title)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(option.mode == .exclude ? Color.orange : Color.secondaryText)
                                        .frame(width: 38)
                                }
                                .buttonStyle(.appSecondaryCompact)
                                .help("Switch \(option.query) to \(option.mode == .include ? "Exclude" : "Include")")
                                .accessibilityLabel("Switch filter mode: \(option.query)")
                                .accessibilityValue(option.mode.title)

                                Button {
                                    filter.pathOptions.removeAll { $0.id == option.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .buttonStyle(.appSecondaryCompact)
                                .help("Delete filter: \(option.query)")
                                .accessibilityLabel("Delete filter: \(option.query)")
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(filter.pathOptions.count) * 36, 144))
                Divider().overlay(Color.subtleBorder).padding(.vertical, 4)
            }

            sectionTitle("FILE EXTENSIONS")
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(extensions, id: \.key) { item in
                        AppDropdownRow(isSelected: !filter.hiddenExtensions.contains(item.key)) {
                            if !filter.hiddenExtensions.insert(item.key).inserted {
                                filter.hiddenExtensions.remove(item.key)
                            }
                        } content: {
                            optionLabel(item.key.isEmpty ? "No extension" : ".\(item.key)", count: item.count)
                        }
                        .accessibilityLabel(item.key.isEmpty
                            ? "Files without an extension, \(item.count)"
                            : ".\(item.key) files, \(item.count)")
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(CGFloat(extensions.count) * 36, 216))

            Divider().overlay(Color.subtleBorder).padding(.vertical, 4)
            sectionTitle("VIEWED STATUS")
            AppDropdownRow(isSelected: filter.includesViewed) {
                filter.includesViewed.toggle()
            } content: {
                optionLabel("Viewed files", count: viewedFileCount)
            }
            AppDropdownRow(isSelected: filter.includesUnviewed) {
                filter.includesUnviewed.toggle()
            } content: {
                optionLabel("Unviewed files", count: files.count - viewedFileCount)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(2)
        .onAppear { isPathFocused = true }
    }

    private func addPathOption() {
        filter.addPathQuery()
        isPathFocused = true
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.appBackground, in: Capsule())
    }

    private func optionLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            countBadge(count)
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }
}

private struct DiffFileFilterModePicker: View {
    @Binding var mode: DiffFileFilter.PathMode
    @State private var hoveredMode: DiffFileFilter.PathMode?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DiffFileFilter.PathMode.allCases, id: \.self) { item in
                Button { mode = item } label: {
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(mode == item ? Color.primary : Color.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .appHeaderSurface(isHovered: hoveredMode == item, restingOpacity: mode == item ? 0.085 : 0)
                }
                .buttonStyle(.plain)
                .onHover { hoveredMode = $0 ? item : nil }
                .accessibilityLabel("\(item.title) new filter")
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
    }
}
