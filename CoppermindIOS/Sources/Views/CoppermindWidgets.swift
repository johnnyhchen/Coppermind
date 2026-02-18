// CoppermindWidgets.swift — Widget views and timeline providers for iOS
// CoppermindIOS
//
// Widgets are defined here as view structs and timeline providers.
// In a full Xcode project these would live in a Widget Extension target.
// The views and providers are kept in the main app for compilation and reuse.

import SwiftUI
import SwiftData
import CoppermindCore

// MARK: - Widget Entry

/// Timeline entry carrying snapshot data for widgets.
struct CoppermindWidgetEntry: Sendable {
    let date: Date

    /// Top priority items for PriorityWidget.
    let topItems: [WidgetNoteItem]

    /// Task stats for TaskCountWidget.
    let taskStats: WidgetTaskStats
}

/// Lightweight note representation for widget display.
struct WidgetNoteItem: Identifiable, Sendable {
    let id: UUID
    let title: String
    let category: NoteCategory
    let priorityScore: Double
    let isOverdue: Bool
}

/// Task completion stats for widget display.
struct WidgetTaskStats: Sendable {
    let total: Int
    let completed: Int
    let overdue: Int

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var remaining: Int { total - completed }

    static let placeholder = WidgetTaskStats(total: 10, completed: 6, overdue: 1)
}

// MARK: - Priority Widget View (Medium — Top 3 Items)

/// A medium-sized widget showing the top 3 highest-priority items.
struct PriorityWidgetView: View {
    let entry: CoppermindWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
                Text("Priority")
                    .font(.subheadline.bold())
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if entry.topItems.isEmpty {
                Spacer()
                Text("No notes yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.topItems.prefix(3)) { item in
                    HStack(spacing: 8) {
                        // Category icon
                        Image(systemName: item.category.iconName)
                            .font(.caption2)
                            .foregroundStyle(item.category.accentColor)
                            .frame(width: 16)

                        // Title
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(item.isOverdue ? .red : .primary)

                        Spacer()

                        // Priority score
                        Text("\(Int(item.priorityScore))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Task Count Widget View (Small — Ring Progress)

/// A small widget showing a ring progress indicator for task completion.
struct TaskCountWidgetView: View {
    let entry: CoppermindWidgetEntry

    private var stats: WidgetTaskStats { entry.taskStats }

    var body: some View {
        VStack(spacing: 8) {
            // Progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                    .frame(width: 56, height: 56)

                // Progress ring
                Circle()
                    .trim(from: 0, to: stats.progress)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                // Center label
                VStack(spacing: 0) {
                    Text("\(stats.remaining)")
                        .font(.system(.title3, design: .rounded).bold())
                    Text("left")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Footer
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("\(stats.completed)/\(stats.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if stats.overdue > 0 {
                Text("\(stats.overdue) overdue")
                    .font(.system(size: 9).bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
    }

    private var ringColor: Color {
        if stats.overdue > 0 { return .red }
        if stats.progress >= 1.0 { return .green }
        return .blue
    }
}

// MARK: - Timeline Provider

/// Provides timeline entries for both Priority and TaskCount widgets.
/// Uses SwiftData to fetch current note state.
///
/// In a real Widget Extension, this would conform to `AppIntentTimelineProvider`.
/// Here we define the data-loading logic as a reusable utility.
struct CoppermindTimelineProvider {

    /// Generate a widget entry from the current SwiftData store.
    @MainActor
    static func currentEntry(modelContext: ModelContext) -> CoppermindWidgetEntry {
        // Fetch non-archived notes sorted by priority
        let topItemEntries: [WidgetNoteItem]
        let taskStats: WidgetTaskStats

        do {
            let descriptor = FetchDescriptor<Note>(
                predicate: #Predicate<Note> { !$0.isArchived },
                sortBy: [SortDescriptor(\.priorityScore, order: .reverse)]
            )
            let notes = try modelContext.fetch(descriptor)

            topItemEntries = notes.prefix(3).map { note in
                WidgetNoteItem(
                    id: note.id,
                    title: note.title,
                    category: note.category,
                    priorityScore: note.priorityScore,
                    isOverdue: note.isOverdue
                )
            }

            let tasks = notes.filter { $0.category == .task }
            taskStats = WidgetTaskStats(
                total: tasks.count,
                completed: tasks.filter { $0.isCompleted == true }.count,
                overdue: tasks.filter(\.isOverdue).count
            )
        } catch {
            topItemEntries = []
            taskStats = WidgetTaskStats(total: 0, completed: 0, overdue: 0)
        }

        return CoppermindWidgetEntry(
            date: .now,
            topItems: topItemEntries,
            taskStats: taskStats
        )
    }

    /// Generate a placeholder entry for widget previews.
    static func placeholder() -> CoppermindWidgetEntry {
        CoppermindWidgetEntry(
            date: .now,
            topItems: [
                WidgetNoteItem(id: UUID(), title: "Review project brief", category: .task, priorityScore: 165, isOverdue: false),
                WidgetNoteItem(id: UUID(), title: "New app idea: habit tracker", category: .idea, priorityScore: 48, isOverdue: false),
                WidgetNoteItem(id: UUID(), title: "Q1 Planning", category: .project, priorityScore: 62, isOverdue: false),
            ],
            taskStats: .placeholder
        )
    }

    /// Generate a snapshot entry for widget gallery.
    static func snapshot() -> CoppermindWidgetEntry {
        placeholder()
    }
}

// MARK: - Preview Helpers

#if DEBUG
@available(iOS 18.0, *)
#Preview("Priority Widget (Medium)") {
    PriorityWidgetView(entry: CoppermindTimelineProvider.placeholder())
        .frame(width: 329, height: 155)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
}

@available(iOS 18.0, *)
#Preview("Task Count Widget (Small)") {
    TaskCountWidgetView(entry: CoppermindTimelineProvider.placeholder())
        .frame(width: 155, height: 155)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
}
#endif
