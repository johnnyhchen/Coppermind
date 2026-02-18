// CoppermindIOS – iOS App Entry Point
import SwiftUI
import SwiftData
import CoppermindCore

@main
struct CoppermindIOSApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [Note.self, Connection.self, AudioRecording.self, NoteGroup.self])
    }
}
