// CategoryTabView.swift — Reusable per-category browsing tab
// CoppermindIOS

import SwiftUI
import SwiftData
import CoppermindCore

// MARK: - Sort Option

/// Sort options available within each category tab.
enum CategorySortOption: String, CaseIterable, Sendable {
    case priority = "Priority"
    case updated  = "Updated"
    case created  = "Created"
    case title    = "Title"
    case dueDate  = "Due Date"
}

// MARK: - Filter Option

/// Quick-filter pills for category tabs.
enum CategoryFilterOption: String, CaseIterable, Sendable {
    case all      = "All"
    case active   = "Active"
    case pinned   = "Pinned"
    case archived = "Archived"
}

// MARK: - CategoryTabView

/// A reusable category-scoped list view.
///
/// Features:
/// - **Search**: full-text search over title + body.
/// - **Sort**: priority, updated, created, title, due date (tasks).
/// - **Filter pills**: All / Active / Pinned / Archived.
/// - **Task tab extras**: overdue highlighting, aggregate progress bar.
/// - **Bucket tab extras**: grouped by `BucketType`.
struct CategoryTabView: View {

    // MARK: - Configuration

    let category: NoteCategory

    // MARK: - Queries

    @Query(sort: \Note.priorityScore, order: .reverse) private var allNotes: [Note]
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var searchText: String = ""
    @State private var sortOption: CategorySortOption = .priority
    @State private var filterOption: CategoryFilterOption = .active
    @State private var selectedNote: Note?

    // MARK: - Derived Data

    /// Notes filtered to this category, then further filtered + sorted.
    private var filteredNotes: [Note] {
        var notes = allNotes.filter { $0.category == category }

        // Filter
        switch filterOption {
        case .all:
            break
        case .active:
            notes = notes.filter { !$0.isArchived && $0.isCompleted != true }
        case .pinned:
            notes = notes.filter(\.isPinned)
        case .archived:
            notes = notes.filter(\.isArchived)
        }

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            notes = notes.filter {
                $0.title.lowercased().contains(query)
                || $0.body.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOption {
        case .priority:
            notes.sort { $0.priorityScore > $1.priorityScore }
        case .updated:
            notes.sort { $0.updatedAt > $1.updatedAt }
        case .created:
            notes.sort { $0.createdAt > $1.createdAt }
        case .title:
            notes.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dueDate:
            notes.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }

        return notes
    }

    // MARK: - Task Stats

    private var taskStats: (total: Int, completed: Int, overdue: Int)? {
        guard category == .task else { return nil }
        let tasks = allNotes.filter { $0.category == .task && !$0.isArchived }
        return (
            total: tasks.count,
            completed: tasks.filter { $0.isCompleted == true }.count,
            overdue: tasks.filter(\.isOverdue).count
        )
    }

    /// Bucket notes grouped by BucketType.
    private var bucketGroups: [(type: BucketType, notes: [Note])] {
        guard category == .bucket else { return [] }
        var map: [BucketType: [Note]] = [:]
        for note in filteredNotes {
            let bt = note.bucketType ?? .other
            map[bt, default: []].append(note)
        }
        return BucketType.allCases.compactMap { type in
            guard let notes = map[type], !notes.isEmpty else { return nil }
            return (type: type, notes: notes)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Task progress bar
                if let stats = taskStats {
                    taskProgressHeader(stats: stats)
                }

                // Filter pills
                filterPillsBar

                // Content
                if category == .bucket && filterOption != .archived {
                    bucketGroupedList
                } else {
                    standardList
                }
            }
            .navigationTitle(category.displayName + "s")
            .searchable(text: $searchText, prompt: "Search \(category.displayName.lowercased())s\u{2026}")
            .navigationDestination(item: $selectedNote) { note in
                IOSNoteDetailView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createNote()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - Task Progress Header

    private func taskProgressHeader(stats: (total: Int, completed: Int, overdue: Int)) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(stats.completed)/\(stats.total) completed")
                    .font(.caption.monospacedDigit())
                Spacer()
                if stats.overdue > 0 {
                    Label("\(stats.overdue) overdue", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
            ProgressView(
                value: stats.total > 0 ? Double(stats.completed) / Double(stats.total) : 0
            )
            .tint(stats.overdue > 0 ? .red : .blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - Filter Pills

    private var filterPillsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CategoryFilterOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.snappy) { filterOption = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                filterOption == option
                                    ? category.accentColor.opacity(0.2)
                                    : Color(.systemGray6)
                            )
                            .foregroundStyle(
                                filterOption == option ? category.accentColor : .secondary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Standard List

    private var standardList: some View {
        List {
            if filteredNotes.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty
                        ? "No \(category.displayName.lowercased())s"
                        : "No results",
                    systemImage: searchText.isEmpty ? category.iconName : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Tap + to create a new \(category.displayName.lowercased())."
                            : "Try a different search."
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredNotes) { note in
                    Button { selectedNote = note } label: {
                        CategoryNoteRow(note: note, showOverdue: category == .task)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if note.isTask {
                            Button {
                                withAnimation { note.completeTask() }
                            } label: {
                                Label("Complete", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            note.isArchived.toggle()
                            note.touch()
                        } label: {
                            Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)

                        Button(role: .destructive) {
                            modelContext.delete(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Bucket Grouped List

    private var bucketGroupedList: some View {
        List {
            if bucketGroups.isEmpty {
                ContentUnavailableView(
                    "No bucket items",
                    systemImage: "tray",
                    description: Text("Add items to your bucket list.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(bucketGroups, id: \.type) { group in
                    Section {
                        ForEach(group.notes) { note in
                            Button { selectedNote = note } label: {
                                BucketNoteRow(note: note)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    note.isArchived.toggle()
                                    note.touch()
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    note.isStarred.toggle()
                                    note.touch()
                                } label: {
                                    Label(
                                        note.isStarred ? "Unstar" : "Star",
                                        systemImage: note.isStarred ? "star.slash" : "star.fill"
                                    )
                                }
                                .tint(.yellow)
                            }
                        }
                    } header: {
                        Label(group.type.rawValue.capitalized, systemImage: bucketIcon(for: group.type))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOption) {
                ForEach(applicableSortOptions, id: \.self) { option in
                    Text(option.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var applicableSortOptions: [CategorySortOption] {
        var opts: [CategorySortOption] = [.priority, .updated, .created, .title]
        if category == .task {
            opts.append(.dueDate)
        }
        return opts
    }

    // MARK: - Actions

    private func createNote() {
        let note = Note(title: "", body: "", category: category, source: .typed)
        if category == .task {
            note.urgency = .medium
        }
        if category == .bucket {
            note.bucketType = .other
        }
        modelContext.insert(note)
        selectedNote = note
    }

    private func bucketIcon(for type: BucketType) -> String {
        switch type {
        case .buy:    return "cart"
        case .read:   return "book"
        case .visit:  return "map"
        case .watch:  return "tv"
        case .listen: return "headphones"
        case .other:  return "ellipsis.circle"
        }
    }
}

// MARK: - Category Note Row

struct CategoryNoteRow: View {
    let note: Note
    var showOverdue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if showOverdue && note.isOverdue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(showOverdue && note.isOverdue ? .red : .primary)
                Spacer()
                if note.isCompleted == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let urgency = note.urgency {
                    Text(urgency.rawValue.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(urgencyColor(urgency))
                }
                if let due = note.dueDate {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(note.isOverdue ? .red : .secondary)
                }
                Spacer()
                Text(note.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func urgencyColor(_ urgency: Urgency) -> Color {
        switch urgency {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .green
        }
    }
}

// MARK: - Bucket Note Row

struct BucketNoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 12) {
            if note.isStarred {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                if let url = note.url, !url.isEmpty {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let price = note.estimatedPrice, price > 0 {
                        Text(price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let loc = note.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(note.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
