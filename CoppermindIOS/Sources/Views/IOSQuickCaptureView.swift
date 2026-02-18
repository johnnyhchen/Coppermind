// IOSQuickCaptureView.swift — iOS quick note capture sheet
// CoppermindIOS

import SwiftUI
import SwiftData
import CoppermindCore

/// A modal sheet for rapid note capture on iOS.
/// Optimized for speed: minimal fields, auto-categorization on save.
struct IOSQuickCaptureView: View {

    // MARK: - State

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var captureBody: String = ""
    @State private var tags: String = ""
    @State private var isSaving: Bool = false
    @FocusState private var isBodyFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Quick entry
                TextField("What's on your mind?", text: $captureBody, axis: .vertical)
                    .font(.body)
                    .lineLimit(3...10)
                    .focused($isBodyFocused)
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Tags
                TextField("Tags (comma separated)", text: $tags)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                Spacer()

                // Character count
                HStack {
                    Spacer()
                    Text("\(captureBody.count) characters")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .navigationTitle("Quick Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveNote() }
                        .disabled(captureBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                isBodyFocused = true
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Save

    private func saveNote() {
        isSaving = true

        // Auto-generate title from first line
        let firstLine = captureBody
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(60)

        let note = Note(
            title: String(firstLine ?? "Quick Note"),
            body: captureBody.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .typed
        )

        modelContext.insert(note)

        isSaving = false
        dismiss()
    }
}
