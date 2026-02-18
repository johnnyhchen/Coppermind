// HomeView.swift — iOS home / priority feed screen
// CoppermindIOS

import SwiftUI
import SwiftData
import CoppermindCore

// MARK: - Feed Section

/// Logical section for the home priority feed.
private enum FeedSection: String, CaseIterable {
    case urgent = "Urgent"
    case important = "Important"
    case browse = "Browse"

    var icon: String {
        switch self {
        case .urgent:    return "exclamationmark.triangle.fill"
        case .important: return "star.fill"
        case .browse:    return "rectangle.stack.fill"
        }
    }

    var tint: Color {
        switch self {
        case .urgent:    return .red
        case .important: return .orange
        case .browse:    return .blue
        }
    }
}

// MARK: - HomeView

/// The iOS home screen presenting a priority-scored feed.
///
/// Layout:
/// - **Pinned / Approaching Deadline** (tasks due within 48 h)
/// - **Urgent**: overdue tasks, high-urgency items
/// - **Important**: medium-priority, recently active
/// - **Browse**: everything else
///
/// Supports pull-to-refresh, swipe-right to complete, swipe-left to archive,
/// and a floating action button for quick Type/Record capture.
struct HomeView: View {

    // MARK: - Queries

    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Note> { !$0.isArchived },
        sort: \Note.priorityScore,
        order: .reverse
    ) private var allNotes: [Note]

    // MARK: - State

    @State private var selectedNote: Note?
    @State private var isRefreshing: Bool = false

    // MARK: - Computed Sections

    /// Tasks due within 48 hours or pinned items.
    private var pinnedApproaching: [Note] {
        let horizon: TimeInterval = 48 * 60 * 60
        return allNotes.filter { note in
            if note.isPinned { return true }
            if note.isTask, let due = note.dueDate, note.isCompleted != true {
                return due.timeIntervalSince(Date.now) <= horizon && due.timeIntervalSince(Date.now) > 0
            }
            return false
        }
    }

    /// Overdue or high-urgency tasks (priority score > 140).
    private var urgentNotes: [Note] {
        allNotes.filter { note in
            if pinnedApproaching.contains(where: { $0.id == note.id }) { return false }
            if note.isOverdue { return true }
            if note.urgency == .high && note.isCompleted != true { return true }
            return note.priorityScore > 140
        }
    }

    /// Medium-importance items (priority score 50–140).
    private var importantNotes: [Note] {
        let pinnedIds = Set(pinnedApproaching.map(\.id))
        let urgentIds = Set(urgentNotes.map(\.id))
        return allNotes.filter { note in
            !pinnedIds.contains(note.id)
            && !urgentIds.contains(note.id)
            && note.priorityScore >= 50
            && note.priorityScore <= 140
        }
    }

    /// Lower-priority items for browsing.
    private var browseNotes: [Note] {
        let usedIds = Set(
            pinnedApproaching.map(\.id)
            + urgentNotes.map(\.id)
            + importantNotes.map(\.id)
        )
        return allNotes.filter { !usedIds.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    // MARK: Pinned / Approaching Deadline
                    if !pinnedApproaching.isEmpty {
                        sectionView(
                            title: "Due Soon",
                            icon: "clock.badge.exclamationmark.fill",
                            tint: .pink,
                            notes: pinnedApproaching
                        )
                    }

                    // MARK: Urgent
                    if !urgentNotes.isEmpty {
                        sectionView(
                            title: FeedSection.urgent.rawValue,
                            icon: FeedSection.urgent.icon,
                            tint: FeedSection.urgent.tint,
                            notes: urgentNotes
                        )
                    }

                    // MARK: Important
                    if !importantNotes.isEmpty {
                        sectionView(
                            title: FeedSection.important.rawValue,
                            icon: FeedSection.important.icon,
                            tint: FeedSection.important.tint,
                            notes: importantNotes
                        )
                    }

                    // MARK: Browse
                    if !browseNotes.isEmpty {
                        sectionView(
                            title: FeedSection.browse.rawValue,
                            icon: FeedSection.browse.icon,
                            tint: FeedSection.browse.tint,
                            notes: browseNotes
                        )
                    }

                    // MARK: Empty State
                    if allNotes.isEmpty {
                        emptyFeedView
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 100) // space for FAB
            }
            .navigationTitle("Coppermind")
            .navigationDestination(item: $selectedNote) { note in
                IOSNoteDetailView(note: note)
            }
            .refreshable {
                await refreshPriorities()
            }
        }
    }

    // MARK: - Section View

    private func sectionView(title: String, icon: String, tint: Color, notes: [Note]) -> some View {
        Section {
            ForEach(notes.prefix(20)) { note in
                HomeFeedCard(note: note)
                    .onTapGesture { selectedNote = note }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if note.isTask {
                            Button {
                                withAnimation { completeNote(note) }
                            } label: {
                                Label("Complete", systemImage: "checkmark")
                            }
                            .tint(.green)
                        } else {
                            Button {
                                withAnimation { note.isPinned.toggle(); note.touch() }
                            } label: {
                                Label(note.isPinned ? "Unpin" : "Pin",
                                      systemImage: note.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(.yellow)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            withAnimation { archiveNote(note) }
                        } label: {
                            Label("Archive", systemImage: "archivebox.fill")
                        }
                        .tint(.orange)
                    }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(notes.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(.regularMaterial)
        }
    }

    // MARK: - Empty State

    private var emptyFeedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Your Coppermind is empty")
                .font(.title3.bold())
            Text("Tap + to capture your first thought")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Actions

    private func completeNote(_ note: Note) {
        note.completeTask()
    }

    private func archiveNote(_ note: Note) {
        note.isArchived = true
        note.touch()
    }

    private func refreshPriorities() async {
        let scorer = PriorityScorer()
        do {
            try scorer.recalculateAll(in: modelContext)
        } catch {
            print("Priority refresh failed: \(error)")
        }
    }
}

// MARK: - Home Feed Card

struct HomeFeedCard: View {
    let note: Note

    private var isApproachingDeadline: Bool {
        guard note.isTask, let due = note.dueDate, note.isCompleted != true else { return false }
        let hours = due.timeIntervalSince(Date.now) / 3600
        return hours > 0 && hours <= 48
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if note.isOverdue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if isApproachingDeadline {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                priorityBadge
            }

            // Body preview
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Footer: category chip + due date + timestamp
            HStack(spacing: 8) {
                categoryChip
                if note.isTask, let due = note.dueDate {
                    Text(due, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(note.isOverdue ? .red : .secondary)
                }
                if note.source == .audio {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                Spacer()
                Text(note.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(note.isOverdue ? .red.opacity(0.4) : .clear, lineWidth: 1.5)
        )
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var categoryChip: some View {
        Text(note.category.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(note.category.accentColor.opacity(0.15))
            .foregroundStyle(note.category.accentColor)
            .clipShape(Capsule())
    }

    private var priorityBadge: some View {
        Text("\(Int(note.priorityScore))")
            .font(.caption2.monospacedDigit().bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor.opacity(0.15))
            .foregroundStyle(priorityColor)
            .clipShape(Capsule())
    }

    private var priorityColor: Color {
        if note.priorityScore > 140 { return .red }
        if note.priorityScore > 80 { return .orange }
        return .green
    }
}
