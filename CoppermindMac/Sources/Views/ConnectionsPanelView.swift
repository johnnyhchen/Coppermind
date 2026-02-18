// ConnectionsPanelView.swift — Connected notes panel for the detail view
// CoppermindMac

import SwiftUI
import SwiftData
import CoppermindCore

/// Displays linked notes grouped by relationship type. Supports add/remove connections.
struct ConnectionsPanelView: View {

    // MARK: - Properties

    let note: Note
    @Environment(\.modelContext) private var modelContext

    @State private var showAddConnection: Bool = false
    @State private var searchText: String = ""

    // MARK: - Computed

    /// All connections grouped by relationship type.
    private var groupedConnections: [String: [Connection]] {
        Dictionary(grouping: note.allConnections) { $0.relationshipType }
    }

    /// Sorted relationship type keys.
    private var sortedRelationshipTypes: [String] {
        groupedConnections.keys.sorted()
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Connections")
                    .font(.headline)
                Text("(\(note.allConnections.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showAddConnection = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .help("Add Connection")
            }

            if note.allConnections.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("No connections yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Connections are discovered automatically or can be added manually.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                // Grouped connections list
                ForEach(sortedRelationshipTypes, id: \.self) { relType in
                    if let connections = groupedConnections[relType] {
                        VStack(alignment: .leading, spacing: 6) {
                            // Group header
                            HStack {
                                Text(relType.capitalized)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Rectangle()
                                    .fill(.quaternary)
                                    .frame(height: 1)
                            }

                            // Connection rows
                            ForEach(connections) { connection in
                                ConnectionRow(
                                    connection: connection,
                                    currentNote: note,
                                    onDelete: { removeConnection(connection) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        .sheet(isPresented: $showAddConnection) {
            AddConnectionSheet(note: note)
        }
    }

    // MARK: - Actions

    private func removeConnection(_ connection: Connection) {
        modelContext.delete(connection)
    }
}

// MARK: - Connection Row

private struct ConnectionRow: View {
    let connection: Connection
    let currentNote: Note
    let onDelete: () -> Void

    var body: some View {
        HStack {
            let otherNote = connection.otherNote(from: currentNote)

            VStack(alignment: .leading, spacing: 2) {
                Text(otherNote.title.isEmpty ? "Untitled" : otherNote.title)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(otherNote.category.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(otherNote.category.accentColor.opacity(0.15))
                        .clipShape(Capsule())

                    if connection.createdBy == .auto {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Strength indicator
            Text("\(Int(connection.strength * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())

            // Remove button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Remove Connection")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Connection Sheet

private struct AddConnectionSheet: View {
    let note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @State private var searchText: String = ""
    @State private var relationshipType: String = "related"

    private var availableNotes: [Note] {
        let connectedIDs = Set(note.allConnections.map { $0.otherNote(from: note).id })
        return allNotes.filter { candidate in
            candidate.id != note.id
            && !connectedIDs.contains(candidate.id)
            && !candidate.isArchived
            && (searchText.isEmpty
                || candidate.title.localizedCaseInsensitiveContains(searchText)
                || candidate.body.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add Connection")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            TextField("Search notes…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Relationship", selection: $relationshipType) {
                Text("Related").tag("related")
                Text("Follow-up").tag("follow-up")
                Text("Contradicts").tag("contradicts")
                Text("Supports").tag("supports")
                Text("Reference").tag("reference")
            }
            .pickerStyle(.segmented)

            List(availableNotes) { candidate in
                Button {
                    addConnection(to: candidate)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                                .font(.subheadline)
                            Text(candidate.body.prefix(60).description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 200)
        }
        .padding()
        .frame(width: 400, height: 420)
    }

    private func addConnection(to target: Note) {
        let connection = Connection(
            sourceNote: note,
            targetNote: target,
            relationshipType: relationshipType,
            strength: 1.0,
            createdBy: .manual
        )
        modelContext.insert(connection)
    }
}
