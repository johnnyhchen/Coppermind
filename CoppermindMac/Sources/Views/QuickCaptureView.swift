// QuickCaptureView.swift — macOS floating quick-capture panel
// CoppermindMac

import SwiftUI
import SwiftData
import CoppermindCore

/// A lightweight, floating panel for rapid note capture.
/// Triggered by ⌘⇧N. Includes text field + record option. Auto-categorizes on submit.
struct QuickCaptureView: View {

    // MARK: - State

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var isRecording: Bool = false
    @State private var isSaving: Bool = false
    @State private var classificationResult: CategoryResult?
    @FocusState private var isTitleFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("Quick Capture")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Title
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)

            // Body
            TextEditor(text: $bodyText)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )

            // Auto-classification indicator
            if let result = classificationResult {
                HStack(spacing: 4) {
                    Image(systemName: result.category.iconName)
                    Text(result.category.displayName)
                        .font(.caption)
                    Text("(\(Int(result.confidence * 100))%)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(result.category.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Actions
            HStack {
                // Record button
                Button {
                    isRecording.toggle()
                } label: {
                    Label(
                        isRecording ? "Stop" : "Record",
                        systemImage: isRecording ? "stop.circle.fill" : "mic.circle"
                    )
                }
                .tint(isRecording ? .red : .secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveNote()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear {
            isTitleFocused = true
        }
        .onChange(of: bodyText) { _, newValue in
            // Auto-classify as the user types (debounced by onChange coalescing)
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 {
                Task {
                    let classifier = CategoryClassifier()
                    let text = [title, newValue].filter { !$0.isEmpty }.joined(separator: ". ")
                    classificationResult = await classifier.classify(text: text)
                }
            }
        }
    }

    // MARK: - Save

    private func saveNote() {
        isSaving = true

        let note = Note(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            category: classificationResult?.category ?? .idea,
            source: .typed
        )

        modelContext.insert(note)

        // Auto-categorize in the background if not already classified
        if classificationResult == nil {
            Task {
                let classifier = CategoryClassifier()
                await classifier.classifyAndApply(to: note)
            }
        }

        isSaving = false
        dismiss()
    }
}
