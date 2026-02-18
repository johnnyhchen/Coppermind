// SidebarView.swift — macOS sidebar navigation
// CoppermindMac

import SwiftUI
import SwiftData
import CoppermindCore

// MARK: - Note Filter

/// Describes which notes to show in the list view.
enum NoteFilter: Equatable, Sendable {
    case all
    case today
    case highPriority
    case recent
    case category(NoteCategory)
    case pinned
    case archived
}

// MARK: - Sidebar Item

/// Navigation items in the macOS sidebar.
enum SidebarItem: Hashable, Identifiable, Sendable {
    // Smart Groups
    case today
    case highPriority
    case recent

    // Categories
    case allNotes
    case category(NoteCategory)

    // System
    case pinned
    case archived

    var id: String {
        switch self {
        case .today:               return "today"
        case .highPriority:        return "highPriority"
        case .recent:              return "recent"
        case .allNotes:            return "allNotes"
        case .category(let cat):   return "cat_\(cat.rawValue)"
        case .pinned:              return "pinned"
        case .archived:            return "archived"
        }
    }

    var displayName: String {
        switch self {
        case .today:               return "Today"
        case .highPriority:        return "High Priority"
        case .recent:              return "Recent"
        case .allNotes:            return "All Notes"
        case .category(let cat):   return cat.displayName
        case .pinned:              return "Pinned"
        case .archived:            return "Archived"
        }
    }

    var icon: String {
        switch self {
        case .today:               return "calendar"
        case .highPriority:        return "flame"
        case .recent:              return "clock"
        case .allNotes:            return "doc.text"
        case .category(let cat):   return cat.iconName
        case .pinned:              return "pin"
        case .archived:            return "archivebox"
        }
    }

    var noteFilter: NoteFilter {
        switch self {
        case .today:               return .today
        case .highPriority:        return .highPriority
        case .recent:              return .recent
        case .allNotes:            return .all
        case .category(let cat):   return .category(cat)
        case .pinned:              return .pinned
        case .archived:            return .archived
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {

    @Binding var selection: SidebarItem?
    @Query(filter: #Predicate<Note> { !$0.isArchived }) private var activeNotes: [Note]
    @Environment(\.modelContext) private var modelContext

    // MARK: - Computed Counts

    private var todayCount: Int {
        let calendar = Calendar.current
        return activeNotes.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    private var highPriorityNotes: [Note] {
        activeNotes.filter { $0.priorityScore >= 80 }
    }

    private var highPriorityCount: Int {
        highPriorityNotes.count
    }

    private var recentCount: Int {
        let threeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
        return activeNotes.filter { $0.updatedAt >= threeDaysAgo }.count
    }

    private func categoryCount(_ category: NoteCategory) -> Int {
        activeNotes.filter { $0.category == category }.count
    }

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            // MARK: Smart Groups
            Section("Smart Groups") {
                sidebarRow(.today, count: todayCount)
                sidebarRow(.highPriority, count: highPriorityCount, showBadge: highPriorityCount > 0)
                sidebarRow(.recent, count: recentCount)
            }

            // MARK: Categories
            Section("Categories") {
                sidebarRow(.category(.idea), count: categoryCount(.idea))
                sidebarRow(.category(.task), count: categoryCount(.task))
                sidebarRow(.category(.project), count: categoryCount(.project))
                sidebarRow(.category(.bucket), count: categoryCount(.bucket))
            }

            // MARK: System
            Section("System") {
                sidebarRow(.allNotes, count: activeNotes.count)
                sidebarRow(.pinned, count: activeNotes.filter(\.isPinned).count)
                sidebarRow(.archived, count: nil)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Coppermind")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newNote, object: nil)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Note")
            }
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem, count: Int?, showBadge: Bool = false) -> some View {
        HStack {
            Label(item.displayName, systemImage: item.icon)
            Spacer()
            if showBadge {
                Text("\(count ?? 0)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.red))
            } else if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(item)
    }
}
