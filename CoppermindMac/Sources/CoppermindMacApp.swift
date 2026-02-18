// CoppermindMac – macOS App Entry Point
import SwiftUI
import SwiftData
import CoppermindCore

@main
struct CoppermindMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Note.self, Connection.self, AudioRecording.self, NoteGroup.self])
    }
}

struct ContentView: View {
    @State private var selectedSidebarItem: SidebarItem? = .allNotes
    @State private var selectedNote: Note?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSidebarItem)
        } content: {
            if let item = selectedSidebarItem {
                NoteListView(filter: item.noteFilter, selectedNote: $selectedNote)
            }
        } detail: {
            if let note = selectedNote {
                NoteDetailView(note: note)
            } else {
                ContentUnavailableView("Select a Note", systemImage: "doc.text", description: Text("Choose a note from the list."))
            }
        }
    }
}
